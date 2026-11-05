import { PaymentServiceError, ehUuid } from '../../services/payments/payment-service'
import { verificarCartao } from '../../services/payments/cartao-service'

/**
 * Resultado do cartao depois da confirmacao do banco (3DS). A tela chama
 * algumas vezes ate o Mercado Pago responder aprovado ou recusado. Sem o
 * rate limit por IP de proposito: ele e compartilhado com o POST do cartao e as
 * consultas bloqueariam a proxima tentativa. So consulta o Mercado Pago quando
 * ha tentativa pendente.
 */
export default defineEventHandler(async (event) => {
  const body = await readBody<{ checkoutToken?: string }>(event).catch(() => ({}) as { checkoutToken?: string })
  const checkoutToken = String(body?.checkoutToken ?? '').trim()
  if (!ehUuid(checkoutToken)) {
    setResponseStatus(event, 400)
    return { error: 'CHECKOUT_INVALIDO' }
  }
  try {
    return await verificarCartao(event, checkoutToken)
  } catch (erro) {
    if (erro instanceof PaymentServiceError) {
      setResponseStatus(event, erro.status)
      return { error: erro.code, message: erro.message }
    }
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO', message: 'Não foi possível consultar o pagamento.' }
  }
})
