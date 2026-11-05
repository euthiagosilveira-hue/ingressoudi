import { PaymentServiceError, ehUuid } from '../../services/payments/payment-service'
import { obterConfigCartao } from '../../services/payments/cartao-service'

/** Diz se o pedido pode ser pago com cartao e devolve a public key da casa. */
export default defineEventHandler(async (event) => {
  const token = String(getQuery(event).token ?? '').trim()
  if (!ehUuid(token)) {
    setResponseStatus(event, 400)
    return { error: 'CHECKOUT_INVALIDO' }
  }
  try {
    return await obterConfigCartao(event, token)
  } catch (erro) {
    if (erro instanceof PaymentServiceError) {
      setResponseStatus(event, erro.status)
      return { error: erro.code, message: erro.message }
    }
    return { disponivel: false, publicKey: null, valor: 0, maxParcelas: 1, tentativasRestantes: 0, email: null }
  }
})
