<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

import {
  aguardarDeviceIdMercadoPago,
  carregarSdkMercadoPago,
  carregarSegurancaMercadoPago,
  type ConfigCartaoPublico
} from '~/utils/cartaoCredito'

/**
 * Formulario de cartao do Mercado Pago (Card Payment Brick). O numero do
 * cartao fica dentro do formulario do Mercado Pago; aqui so chega o token de
 * uso unico, que vai para o servidor cobrar. Quando o banco pede confirmacao
 * (3DS), abre a tela do banco (Status Screen Brick) e consulta o resultado.
 */
const props = defineProps<{
  checkoutToken: string
  config: ConfigCartaoPublico
}>()

const emit = defineEmits<{
  aprovado: []
}>()

const CONTAINER_ID = 'cartao-brick-ingressoudi'
const CONTAINER_3DS_ID = 'cartao-3ds-ingressoudi'
const INTERVALO_CONSULTA_MS = 4000
const LIMITE_CONSULTA_MS = 6 * 60 * 1000

const carregandoForm = ref(true)
const processando = ref(false)
const recusa = ref('')
const erro = ref('')
const restantes = ref(props.config.tentativasRestantes)
const bloqueado = ref(props.config.tentativasRestantes <= 0)
const emDesafio = ref(false)

interface BrickController {
  unmount: () => void
}
interface FormDataBrick {
  token: string
  issuer_id?: string | number
  payment_method_id: string
  installments: number
  payer?: { email?: string; identification?: { type?: string; number?: string } }
}
interface RespostaCartao {
  status?: 'APROVADO' | 'RECUSADO' | 'PENDENTE' | 'DESAFIO'
  mensagem?: string
  tentativasRestantes?: number
  desafio?: { paymentId: string; externalResourceUrl: string; creq: string }
  error?: string
  message?: string
}

let controller: BrickController | null = null
let controller3ds: BrickController | null = null
let consultaTimer: ReturnType<typeof setTimeout> | null = null
let consultaInicio = 0
let consultando = false
let encerrado = false

async function montar() {
  if (bloqueado.value || !props.config.publicKey) return
  carregandoForm.value = true
  erro.value = ''
  carregarSegurancaMercadoPago()
  try {
    const MercadoPago = await carregarSdkMercadoPago()
    const mp = new MercadoPago(props.config.publicKey, { locale: 'pt-BR' })
    await nextTick()
    controller = await mp.bricks().create('cardPayment', CONTAINER_ID, {
      initialization: {
        amount: props.config.valor,
        ...(props.config.email ? { payer: { email: props.config.email } } : {})
      },
      customization: {
        paymentMethods: { minInstallments: 1, maxInstallments: props.config.maxParcelas, types: { excluded: ['debit_card', 'prepaid_card'] } },
        visual: { style: { theme: 'dark' }, texts: { formTitle: 'Cartão de crédito' } }
      },
      callbacks: {
        onReady: () => {
          carregandoForm.value = false
        },
        onSubmit: (formData: FormDataBrick) => pagar(formData),
        onError: () => {
          carregandoForm.value = false
        }
      }
    })
  } catch {
    carregandoForm.value = false
    erro.value = 'Não foi possível abrir o formulário do cartão. Recarregue a página ou pague com Pix.'
  }
}

function desmontar() {
  try {
    controller?.unmount()
  } catch {
    // o Brick pode ja ter sido removido
  }
  controller = null
}

function desmontar3ds() {
  try {
    controller3ds?.unmount()
  } catch {
    // idem
  }
  controller3ds = null
}

function pararConsulta() {
  if (consultaTimer) clearTimeout(consultaTimer)
  consultaTimer = null
  if (import.meta.client) window.removeEventListener('message', aoMensagemDoBanco)
}

/** Volta para o formulario (ou bloqueia) depois de uma recusa. */
function refazerFormulario() {
  desmontar()
  if (restantes.value <= 0) {
    bloqueado.value = true
    return
  }
  void montar()
}

function concluirAprovado() {
  pararConsulta()
  desmontar3ds()
  emDesafio.value = false
  emit('aprovado')
}

/** Abre a confirmacao do banco (3DS) dentro da pagina. */
async function abrirDesafio(desafio: NonNullable<RespostaCartao['desafio']>) {
  emDesafio.value = true
  desmontar()
  try {
    const MercadoPago = await carregarSdkMercadoPago()
    const mp = new MercadoPago(props.config.publicKey as string, { locale: 'pt-BR' })
    await nextTick()
    controller3ds = await mp.bricks().create('statusScreen', CONTAINER_3DS_ID, {
      initialization: {
        paymentId: desafio.paymentId,
        additionalInfo: { externalResourceURL: desafio.externalResourceUrl, creq: desafio.creq }
      },
      customization: { visual: { style: { theme: 'dark' }, hideStatusDetails: true, hideTransactionDate: true } },
      callbacks: {
        onReady: () => {},
        onError: () => {}
      }
    })
  } catch {
    erro.value = 'Não foi possível abrir a confirmação do banco. Tente de novo ou pague com Pix.'
  }
  consultaInicio = Date.now()
  window.addEventListener('message', aoMensagemDoBanco)
  agendarConsulta(INTERVALO_CONSULTA_MS)
}

function aoMensagemDoBanco(e: MessageEvent) {
  const dados = e.data as { status?: unknown } | null
  if (dados && typeof dados === 'object' && dados.status === 'COMPLETE') agendarConsulta(500)
}

function agendarConsulta(ms: number) {
  if (encerrado) return
  if (consultaTimer) clearTimeout(consultaTimer)
  consultaTimer = setTimeout(() => void consultar(), ms)
}

async function consultar() {
  if (consultando || encerrado) return
  consultando = true
  try {
    const r = await $fetch<RespostaCartao>('/api/payments/cartao-status', {
      method: 'POST',
      body: { checkoutToken: props.checkoutToken }
    })
    if (r.status === 'APROVADO') {
      concluirAprovado()
      return
    }
    if (r.status === 'RECUSADO') {
      pararConsulta()
      desmontar3ds()
      emDesafio.value = false
      recusa.value = r.mensagem ?? 'O pagamento não foi aprovado.'
      restantes.value = r.tentativasRestantes ?? restantes.value
      refazerFormulario()
      return
    }
  } catch {
    // falha de rede: tenta de novo no proximo ciclo
  } finally {
    consultando = false
  }
  if (Date.now() - consultaInicio > LIMITE_CONSULTA_MS) {
    // O aviso do Mercado Pago ainda confirma depois; a pagina atualiza sozinha.
    concluirAprovado()
    return
  }
  agendarConsulta(INTERVALO_CONSULTA_MS)
}

async function pagar(formData: FormDataBrick): Promise<void> {
  processando.value = true
  recusa.value = ''
  erro.value = ''
  try {
    const deviceId = await aguardarDeviceIdMercadoPago()
    const resposta = await $fetch<RespostaCartao>('/api/payments/cartao', {
      method: 'POST',
      body: {
        checkoutToken: props.checkoutToken,
        token: formData.token,
        paymentMethodId: formData.payment_method_id,
        issuerId: formData.issuer_id ?? null,
        installments: formData.installments,
        payerEmail: formData.payer?.email ?? null,
        identificationType: formData.payer?.identification?.type ?? null,
        identificationNumber: formData.payer?.identification?.number ?? null,
        deviceId
      }
    })
    if (resposta.status === 'APROVADO' || resposta.status === 'PENDENTE') {
      // Deixa o Brick concluir o onSubmit antes de remover o formulario.
      setTimeout(() => {
        desmontar()
        emit('aprovado')
      }, 0)
      return
    }
    if (resposta.status === 'DESAFIO' && resposta.desafio) {
      // O banco tem 30s para comecar a confirmacao: abre ja.
      const desafio = resposta.desafio
      restantes.value = resposta.tentativasRestantes ?? restantes.value
      setTimeout(() => void abrirDesafio(desafio), 0)
      return
    }
    recusa.value = resposta.mensagem ?? 'O pagamento não foi aprovado.'
    restantes.value = resposta.tentativasRestantes ?? Math.max(0, restantes.value - 1)
  } catch (e) {
    const dados = (e as { data?: { error?: string; message?: string } })?.data
    if (dados?.error === 'LIMITE_TENTATIVAS') restantes.value = 0
    erro.value = dados?.message ?? 'Não foi possível processar o cartão. Tente de novo ou pague com Pix.'
  } finally {
    processando.value = false
  }
  // O token do cartao vale uma vez: refaz o formulario para nova tentativa,
  // depois que o Brick concluir o onSubmit.
  setTimeout(refazerFormulario, 0)
}

onMounted(() => {
  void montar()
})

onBeforeUnmount(() => {
  encerrado = true
  pararConsulta()
  desmontar()
  desmontar3ds()
})
</script>

<template>
  <div class="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950/40 p-4">
    <p class="text-xs text-zinc-500">
      Até {{ props.config.maxParcelas }}x. Os dados do cartão ficam com o Mercado Pago, não passam pelo Ingressoudi.
    </p>

    <p
      v-if="recusa"
      role="alert"
      class="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-200"
    >
      {{ recusa }}
    </p>
    <p
      v-if="erro"
      role="alert"
      class="rounded-lg border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-200"
    >
      {{ erro }}
    </p>

    <template v-if="emDesafio">
      <p class="rounded-lg border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-100" aria-live="polite">
        O banco do cartão pediu para confirmar a compra. Siga as instruções abaixo (app do banco, SMS ou senha). Não feche esta página.
      </p>
      <div :id="CONTAINER_3DS_ID" />
    </template>

    <p v-else-if="bloqueado" class="rounded-lg border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-100">
      Limite de tentativas no cartão atingido para este pedido. Pague com Pix.
    </p>

    <template v-else>
      <p v-if="processando" class="text-sm text-zinc-300" aria-busy="true">Processando pagamento...</p>
      <p v-else-if="carregandoForm" class="text-sm text-zinc-400" aria-busy="true">Carregando formulário do cartão...</p>
      <div :id="CONTAINER_ID" />
    </template>
  </div>
</template>
