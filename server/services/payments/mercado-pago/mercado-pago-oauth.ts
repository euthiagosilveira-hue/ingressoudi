/**
 * OAuth do Mercado Pago (modelo marketplace): cada organizacao conecta a propria
 * conta e o Ingressoudi recebe um access_token para cobrar em nome dela.
 * Modulo sem auto-imports do Nuxt (testavel com node --test).
 */

const AUTH_URL = 'https://auth.mercadopago.com/authorization'
const TOKEN_URL = 'https://api.mercadopago.com/oauth/token'

export interface MpTokenResposta {
  access_token: string
  refresh_token?: string | null
  user_id: number | string
  public_key?: string | null
  expires_in?: number | null
  live_mode?: boolean | null
}

export function montarUrlAutorizacao(params: {
  clientId: string
  redirectUri: string
  state: string
}): string {
  const url = new URL(AUTH_URL)
  url.searchParams.set('client_id', params.clientId)
  url.searchParams.set('response_type', 'code')
  url.searchParams.set('platform_id', 'mp')
  url.searchParams.set('state', params.state)
  url.searchParams.set('redirect_uri', params.redirectUri)
  return url.toString()
}

async function postToken(corpo: Record<string, unknown>): Promise<MpTokenResposta> {
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(corpo)
  })
  if (!response.ok) {
    // Nunca logar o corpo da requisicao (contem client_secret/code).
    throw new Error(`Falha no OAuth do Mercado Pago (HTTP ${response.status}).`)
  }
  const dados = (await response.json()) as MpTokenResposta
  if (!dados?.access_token || !dados?.user_id) {
    throw new Error('Resposta do OAuth do Mercado Pago sem access_token/user_id.')
  }
  return dados
}

export function trocarCodigoPorToken(params: {
  clientId: string
  clientSecret: string
  code: string
  redirectUri: string
  testToken?: boolean
}): Promise<MpTokenResposta> {
  return postToken({
    client_id: params.clientId,
    client_secret: params.clientSecret,
    grant_type: 'authorization_code',
    code: params.code,
    redirect_uri: params.redirectUri,
    ...(params.testToken ? { test_token: true } : {})
  })
}

export function renovarToken(params: {
  clientId: string
  clientSecret: string
  refreshToken: string
}): Promise<MpTokenResposta> {
  return postToken({
    client_id: params.clientId,
    client_secret: params.clientSecret,
    grant_type: 'refresh_token',
    refresh_token: params.refreshToken
  })
}

/** Renova quando faltar menos de 7 dias para expirar (token vale ~180 dias). */
export function precisaRenovar(expiraEm: string | null | undefined, agoraMs: number): boolean {
  if (!expiraEm) return false
  const limite = Date.parse(expiraEm)
  if (Number.isNaN(limite)) return false
  return limite - agoraMs < 7 * 24 * 60 * 60 * 1000
}
