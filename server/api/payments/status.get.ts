import {
  PaymentServiceError,
  consultarStatus,
  ehUuid
} from '../../services/payments/payment-service'

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const token = String(getQuery(event).token ?? '').trim()

  if (!ehUuid(token)) {
    setResponseStatus(event, 400)
    return { error: 'CHECKOUT_INVALIDO' }
  }

  try {
    return await consultarStatus(event, token, config.mercadoPagoAccessToken)
  } catch (erro) {
    if (erro instanceof PaymentServiceError) {
      setResponseStatus(event, erro.status)
      return { error: erro.code, message: erro.message }
    }
    setResponseStatus(event, 503)
    return { error: 'PAGAMENTO_INDISPONIVEL', message: 'Pagamento Pix temporariamente indisponível.' }
  }
})
