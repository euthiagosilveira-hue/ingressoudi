import { serverSupabaseServiceRole } from '#supabase/server'

function ehUuid(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valor)
}

/**
 * Cria (ou renova) o link de compartilhamento de UM ingresso.
 * Valida o acesso ao pedido (checkout_token OU recovery_token) no backend.
 * Nunca devolve checkout_token/recovery_token/qr_token.
 */
export default defineEventHandler(async (event) => {
  const body = await readBody<{
    checkoutToken?: string
    recoveryToken?: string
    ingressoId?: string
  }>(event).catch(() => ({}))

  const ingressoId = String(body?.ingressoId ?? '').trim()
  const checkoutToken =
    typeof body?.checkoutToken === 'string' && body.checkoutToken.trim()
      ? body.checkoutToken.trim()
      : null
  const recoveryToken =
    typeof body?.recoveryToken === 'string' && body.recoveryToken.trim()
      ? body.recoveryToken.trim()
      : null

  if (!ehUuid(ingressoId) || (!checkoutToken && !recoveryToken)) {
    setResponseStatus(event, 400)
    return { error: 'DADOS_INVALIDOS' }
  }

  const client = serverSupabaseServiceRole(event)
  const { data, error } = await client.rpc('criar_compartilhamento_ingresso', {
    p_checkout_token: checkoutToken,
    p_recovery_token: recoveryToken,
    p_ingresso_id: ingressoId
  })

  if (error) {
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }

  const resultado = (data ?? {}) as { ok?: boolean; token?: string }
  if (!resultado.ok || !resultado.token) {
    setResponseStatus(event, 403)
    return { error: 'COMPARTILHAMENTO_NAO_PERMITIDO' }
  }

  const origin = getRequestURL(event).origin
  return { shareUrl: `${origin}/ingresso/${resultado.token}` }
})
