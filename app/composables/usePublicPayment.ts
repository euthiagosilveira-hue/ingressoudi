import { computed, onMounted, onUnmounted, ref } from 'vue'

import {
  PagamentoError,
  criarPagamentoPendente,
  mensagemPagamentoErro,
  obterCheckoutPedido
} from '~/services/public/pagamentos'
import type {
  CheckoutPublico,
  PagamentoErrorCode,
  PagamentoEstado
} from '~/types/checkoutPagamento'

const INTERVALO_POLLING_MS = 5000

function ehUuid(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valor)
}

/**
 * Orquestra a tela de pagamento publico usando o checkout_token.
 * O banco e a fonte de verdade; o relogio local so formata o countdown.
 */
export function usePublicPayment() {
  const route = useRoute()

  const token = computed(() => {
    const valor = route.query.token
    return typeof valor === 'string' && ehUuid(valor) ? valor : null
  })

  const checkout = ref<CheckoutPublico | null>(null)
  const carregando = ref(true)
  const erro = ref<PagamentoErrorCode | null>(null)
  const segundos = ref(0)
  const pix = ref<{ pixCopyPaste: string | null; pixQrCode: string | null; expiresAt: string | null } | null>(null)
  const pixCarregando = ref(false)
  const pixErro = ref(false)
  const verificandoExpiracao = ref(false)

  let timer: ReturnType<typeof setInterval> | null = null
  let pollTimer: ReturnType<typeof setInterval> | null = null

  const estado = computed<PagamentoEstado>(() => {
    if (carregando.value) return 'CARREGANDO'
    if (!token.value) return 'NAO_ENCONTRADO'
    if (erro.value) return 'ERRO'
    const atual = checkout.value
    if (!atual) return 'NAO_ENCONTRADO'

    const pagamentoStatus = atual.pagamento?.status
    if (atual.pedidoStatus === 'PAGO' || pagamentoStatus === 'APROVADO') return 'PAGO'
    if (atual.pedidoStatus === 'CANCELADO' || pagamentoStatus === 'CANCELADO') return 'CANCELADO'
    if (atual.pedidoStatus === 'EXPIRADO' || pagamentoStatus === 'EXPIRADO') return 'EXPIRADO'
    if (pagamentoStatus === 'REJEITADO') return 'REJEITADO'
    if (pagamentoStatus === 'REEMBOLSADO') return 'REEMBOLSADO'
    return 'PENDENTE'
  })

  const expiraEm = computed(
    () => checkout.value?.pagamento?.expiraEm ?? checkout.value?.reservaExpiraEm ?? null
  )

  const textoCountdown = computed(() => {
    const total = Math.max(segundos.value, 0)
    const minutos = Math.floor(total / 60)
    const resto = total % 60
    return `${String(minutos).padStart(2, '0')}:${String(resto).padStart(2, '0')}`
  })

  const tempoEsgotado = computed(
    () => estado.value === 'PENDENTE' && expiraEm.value !== null && segundos.value <= 0
  )

  const mensagemErro = computed(() => (erro.value ? mensagemPagamentoErro(erro.value) : ''))

  function recalcular() {
    if (!expiraEm.value) {
      segundos.value = 0
      return
    }
    const alvo = Date.parse(expiraEm.value)
    segundos.value = Number.isNaN(alvo)
      ? 0
      : Math.max(0, Math.floor((alvo - Date.now()) / 1000))
  }

  function pararTimer() {
    if (timer) {
      clearInterval(timer)
      timer = null
    }
  }

  function iniciarTimer() {
    pararTimer()
    recalcular()
    // Nao reinicia em estado nao-pendente nem quando o tempo ja esgotou.
    if (estado.value !== 'PENDENTE' || segundos.value <= 0) return

    timer = setInterval(() => {
      recalcular()
      if (segundos.value <= 0) {
        pararTimer()
        void finalizarExpiracao()
      }
    }, 1000)
  }

  function pararPolling() {
    if (pollTimer) {
      clearInterval(pollTimer)
      pollTimer = null
    }
  }

  /** Polling moderado enquanto o pagamento estiver pendente e a reserva valida. */
  function iniciarPolling() {
    pararPolling()
    if (estado.value !== 'PENDENTE' || tempoEsgotado.value) return

    pollTimer = setInterval(() => {
      if (estado.value !== 'PENDENTE' || tempoEsgotado.value) {
        pararPolling()
        return
      }
      void (async () => {
        await sincronizarStatus()
        if (!pix.value?.pixCopyPaste) await carregarPix()
        if (estado.value !== 'PENDENTE') pararPolling()
      })()
    }, INTERVALO_POLLING_MS)
  }

  function tratarErro(e: unknown) {
    erro.value = e instanceof PagamentoError ? e.code : 'ERRO_INESPERADO'
  }

  async function buscar(): Promise<CheckoutPublico | null> {
    if (!token.value) return null
    return obterCheckoutPedido(token.value)
  }

  /** Somente leitura: usado pelo botao "Atualizar status" e pelo countdown. */
  async function atualizar() {
    if (!token.value) {
      checkout.value = null
      erro.value = null
      carregando.value = false
      return
    }
    try {
      erro.value = null
      checkout.value = await buscar()
    } catch (e) {
      tratarErro(e)
      checkout.value = null
    } finally {
      carregando.value = false
      iniciarTimer()
      void sincronizarStatus()
      void carregarPix()
      iniciarPolling()
    }
  }

  /** Carga inicial: recupera e, se necessario, cria/reutiliza o pagamento. */
  async function carregar() {
    carregando.value = true
    erro.value = null

    if (!token.value) {
      checkout.value = null
      carregando.value = false
      return
    }

    try {
      let atual = await buscar()
      if (atual && atual.pedidoStatus === 'RESERVADO' && !atual.pagamento) {
        await criarPagamentoPendente(token.value)
        atual = await buscar()
      }
      checkout.value = atual
    } catch (e) {
      tratarErro(e)
      checkout.value = null
    } finally {
      carregando.value = false
      iniciarTimer()
      void sincronizarStatus()
      void carregarPix()
      iniciarPolling()
    }
  }

  /** Busca/gera o Pix real no backend (nunca chama o provider no cliente). */
  async function carregarPix() {
    if (!token.value || estado.value !== 'PENDENTE') return
    if (tempoEsgotado.value || verificandoExpiracao.value) return
    if (pix.value?.pixCopyPaste) return

    pixCarregando.value = true
    pixErro.value = false
    try {
      const resposta = await $fetch<{
        pixCopyPaste?: string | null
        pixQrCode?: string | null
        expiresAt?: string | null
        error?: string
      }>('/api/payments/pix', { method: 'POST', body: { checkoutToken: token.value } })
      if (resposta && !resposta.error) {
        pix.value = {
          pixCopyPaste: resposta.pixCopyPaste ?? null,
          pixQrCode: resposta.pixQrCode ?? null,
          expiresAt: resposta.expiresAt ?? null
        }
        if (!pix.value.pixCopyPaste && !pix.value.pixQrCode) {
          pix.value = null
          pixErro.value = true
        }
      } else {
        pixErro.value = true
      }
    } catch {
      pixErro.value = true
    } finally {
      pixCarregando.value = false
    }
  }

  /**
   * Quando o contador local zera: para os timers e faz UMA reconciliacao final
   * com o backend (que confere o provedor e so entao expira, se aplicavel).
   */
  async function finalizarExpiracao() {
    if (verificandoExpiracao.value) return
    pararTimer()
    pararPolling()
    verificandoExpiracao.value = true
    try {
      await $fetch('/api/payments/status', { query: { token: token.value } }).catch(() => null)
      const atual = await buscar()
      if (atual) checkout.value = atual
    } catch (e) {
      tratarErro(e)
    } finally {
      verificandoExpiracao.value = false
    }

    iniciarTimer()
    if (estado.value === 'PENDENTE' && segundos.value > 0) {
      iniciarPolling()
    }
  }

  /**
   * Caminho de recuperacao: consulta o status no backend (que confere a Order
   * oficial e confirma se aprovada) e, se mudou, re-le o checkout.
   */
  async function sincronizarStatus() {
    if (!token.value) return
    try {
      const resposta = await $fetch<{ status?: string; error?: string }>('/api/payments/status', {
        query: { token: token.value }
      })
      const status = resposta?.status
      if (status && status !== checkout.value?.pagamento?.status) {
        const atualizado = await buscar()
        if (atualizado) checkout.value = atualizado
      }
    } catch {
      // silencioso: a tela segue com o ultimo estado conhecido
    }
  }

  onMounted(() => {
    void carregar()
  })

  onUnmounted(() => {
    pararTimer()
    pararPolling()
  })

  return {
    token,
    checkout,
    carregando,
    erro,
    mensagemErro,
    estado,
    segundos,
    textoCountdown,
    tempoEsgotado,
    pix,
    pixCarregando,
    pixErro,
    verificandoExpiracao,
    carregar,
    atualizar,
    tentarPix: carregarPix
  }
}
