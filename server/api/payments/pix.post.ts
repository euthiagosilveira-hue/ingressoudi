import {
  PaymentServiceError,
  criarPix,
  ehUuid
} from '../../services/payments/payment-service'

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const accessToken = config.mercadoPagoAccessToken

  const body = await readBody<{ checkoutToken?: string }>(event).catch(() => ({}))
  const checkoutToken = String(body?.checkoutToken ?? '').trim()

  if (!ehUuid(checkoutToken)) {
    setResponseStatus(event, 400)
    return { error: 'CHECKOUT_INVALIDO' }
  }

  if (!accessToken) {
    setResponseStatus(event, 503)
    return {
      error: 'PAGAMENTO_INDISPONIVEL',
      message: 'Pagamento Pix temporariamente indisponível.'
    }
  }

  try {
    const autoApproveTestEnabled =
      String(config.mercadoPagoTestAutoApprovePix ?? 'false') === 'true'
    return await criarPix(event, checkoutToken, accessToken, autoApproveTestEnabled)
  } catch (erro) {
    if (erro instanceof PaymentServiceError) {
      setResponseStatus(event, erro.status)
      return { error: erro.code, message: erro.message }
    }
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }
})
