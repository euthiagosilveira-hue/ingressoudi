<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

import {
  aguardarDeviceIdMercadoPago,
  carregarSdkMercadoPago,
  carregarSegurancaMercadoPago,
  type ConfigCartaoPublico } from '~/utils/cartaoCredito'

/**
 * Formulario de cartao do Mercado Pago (Card Payment Brick). O numero do
 * cartao fica dentro do formulario do Mercado Pago; aqui so chega o token de
 * uso unico, que vai para o servidor cobrar.
 */
const props = defineProps<{
  checkoutToken: string
  config: ConfigCartaoPublico
}>()

const emit = defineEmits<{
  aprovado: []
}>()

const CONTAINER_ID = 'cartao-brick-ingressoudi'

const carregandoForm = ref(true)
const processando = ref(false)
const recusa = ref('')
const erro = ref('')
const restantes = ref(props.config.tentativasRestantes)
const bloqueado = ref(props.config.tentativasRestantes <= 0)

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

let controller: BrickController | null = null

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

async function pagar(formData: FormDataBrick): Promise<void> {
  processando.value = true
  recusa.value = ''
  erro.value = ''
  try {
    const deviceId = await aguardarDeviceIdMercadoPago()
    const resposta = await $fetch<{
      status?: 'APROVADO' | 'RECUSADO' | 'PENDENTE'
      mensagem?: string
      tentativasRestantes?: number
      error?: string
      message?: string
    }>('/api/payments/cartao', {
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
  setTimeout(() => {
    desmontar()
    if (restantes.value <= 0) {
      bloqueado.value = true
      return
    }
    void montar()
  }, 0)
}

onMounted(() => {
  void montar()
})

onBeforeUnmount(desmontar)
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

    <p v-if="bloqueado" class="rounded-lg border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-100">
      Limite de tentativas no cartão atingido para este pedido. Pague com Pix.
    </p>

    <template v-else>
      <p v-if="processando" class="text-sm text-zinc-300" aria-busy="true">Processando pagamento...</p>
      <p v-else-if="carregandoForm" class="text-sm text-zinc-400" aria-busy="true">Carregando formulário do cartão...</p>
      <div :id="CONTAINER_ID" />
    </template>
  </div>
</template>
