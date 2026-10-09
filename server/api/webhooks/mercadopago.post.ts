import { serverSupabaseServiceRole } from '#supabase/server'

import { ehUuid } from '../../services/payments/payment-service'
import { MercadoPagoProvider } from '../../services/payments/mercado-pago/mercado-pago-provider'
import { validarAssinaturaMp } from '../../services/payments/mercado-pago/mercado-pago-signature'

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const secret = config.mercadoPagoWebhookSecret
  const accessToken = config.mercadoPagoAccessToken

  const query = getQuery(event)
  const body = await readBody<{ data?: { id?: string } }>(event).catch(() => ({}))
  const dataId = String(query['data.id'] ?? body?.data?.id ?? '') || null

  const xSignature = getHeader(event, 'x-signature') ?? null
  const xRequestId = getHeader(event, 'x-request-id') ?? null

  if (!secret) {
    setResponseStatus(event, 500)
    return { error: 'WEBHOOK_NAO_CONFIGURADO' }
  }

  const assinaturaValida = validarAssinaturaMp({ xSignature, xRequestId, dataId }, secret)
  if (!assinaturaValida) {
    setResponseStatus(event, 401)
    return { error: 'ASSINATURA_INVALIDA' }
  }

  if (!dataId) {
    setResponseStatus(event, 400)
    return { error: 'DATA_ID_AUSENTE' }
  }

  if (!accessToken) {
    setResponseStatus(event, 503)
    return { error: 'PAGAMENTO_INDISPONIVEL' }
  }

  // Nunca confiar apenas no payload: sempre consultar a Order oficial.
  const provider = new MercadoPagoProvider(accessToken)
  const charge = await provider.getCharge(dataId)

  if (charge.status === 'APROVADO' && ehUuid(charge.externalReference)) {
    const client = serverSupabaseServiceRole(event)
    const { error } = await client.rpc('confirmar_pagamento', {
      p_pagamento_id: charge.externalReference,
      p_transaction_id: charge.transactionId,
      p_referencia_externa: charge.externalReference
    })
    if (error) {
      setResponseStatus(event, 500)
      return { error: 'ERRO_CONFIRMACAO' }
    }
  }

  return { ok: true }
})
