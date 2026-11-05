import { PaymentServiceError, ehUuid } from '../../services/payments/payment-service'
import { pagarComCartao } from '../../services/payments/cartao-service'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'
import { limitar } from '../../utils/rate-limit'

interface CorpoCartao {
  checkoutToken?: string
  token?: string
  paymentMethodId?: string
  issuerId?: string | number | null
  installments?: number
  payerEmail?: string | null
  identificationType?: string | null
  identificationNumber?: string | null
  deviceId?: string | null
}

/**
 * Paga o pedido com cartao. Recebe so o token do cartao gerado pelo Brick no
 * navegador; valor, taxa e parcelas maximas sao conferidos no servidor.
 */
export default defineEventHandler(async (event) => {
  if (!limitar(event, 15)) {
    setResponseStatus(event, 429)
    return { error: 'LIMITE_TENTATIVAS', message: 'Muitas tentativas. Aguarde um minuto.' }
  }

  const config = useRuntimeConfig(event)
  const body = await readBody<CorpoCartao>(event).catch(() => ({}) as CorpoCartao)
  const checkoutToken = String(body?.checkoutToken ?? '').trim()
  if (!ehUuid(checkoutToken)) {
    setResponseStatus(event, 400)
    return { error: 'CHECKOUT_INVALIDO' }
  }

  if (String(config.mercadoPagoTokenKey ?? '').length < 32) {
    await alertarErroPagamento(event, {
      tipo: 'CONFIGURACAO',
      mensagem: 'MERCADO_PAGO_TOKEN_KEY ausente ou curta na Vercel: nenhum cartão pode ser cobrado.'
    })
    setResponseStatus(event, 503)
    return { error: 'PAGAMENTO_INDISPONIVEL', message: 'Pagamento com cartão temporariamente indisponível.' }
  }

  try {
    return await pagarComCartao(event, checkoutToken, {
      token: String(body.token ?? ''),
      paymentMethodId: String(body.paymentMethodId ?? ''),
      issuerId: body.issuerId ?? null,
      installments: Number(body.installments),
      payerEmail: body.payerEmail ?? null,
      identificationType: body.identificationType ?? null,
      identificationNumber: body.identificationNumber ?? null,
      deviceId: body.deviceId ?? null
    })
  } catch (erro) {
    if (erro instanceof PaymentServiceError) {
      setResponseStatus(event, erro.status)
      return { error: erro.code, message: erro.message }
    }
    await alertarErroPagamento(event, {
      tipo: 'CARTAO',
      mensagem: 'Erro inesperado ao cobrar cartão.',
      detalhe: { erro: erro instanceof Error ? erro.message : 'erro' }
    })
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO', message: 'Não foi possível processar o cartão. Tente de novo ou pague com Pix.' }
  }
})
