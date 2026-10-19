import type { H3Event } from 'h3'
import type { serverSupabaseServiceRole } from '#supabase/server'

type ClienteServiceRole = ReturnType<typeof serverSupabaseServiceRole>

export type TipoLinkConvite = 'invite' | 'recovery'

/**
 * URL publica canonica (NUXT_PUBLIC_SITE_URL). Evita depender de
 * getRequestURL().origin, que pode resolver localhost/host interno atras de proxy.
 */
export function urlDoSite(event: H3Event): string {
  const config = useRuntimeConfig(event)
  return String(config.public.siteUrl || getRequestURL(event).origin).replace(/\/+$/, '')
}

/** Link que a pessoa abre para aceitar o convite (a pagina pede um clique antes de usar o token). */
export function montarLinkConvite(siteUrl: string, tokenHash: string, tipo: TipoLinkConvite): string {
  const params = new URLSearchParams({ token_hash: tokenHash, tipo })
  return `${siteUrl}/auth/convite?${params.toString()}`
}

interface OpcoesLinkConvite {
  email: string
  tipo: TipoLinkConvite
  siteUrl: string
  dados?: Record<string, unknown>
}

interface ResultadoLinkConvite {
  link: string
  usuarioId: string
}

/**
 * Gera o link de convite pelo Supabase Auth Admin SEM enviar e-mail
 * (generateLink). Para 'invite' cria o usuario no Auth quando ele nao existe.
 * Lanca o erro do Supabase em caso de falha.
 */
export async function gerarLinkConvite(
  admin: ClienteServiceRole,
  { email, tipo, siteUrl, dados }: OpcoesLinkConvite
): Promise<ResultadoLinkConvite> {
  const redirectTo = `${siteUrl}/auth/convite`
  const { data, error } =
    tipo === 'invite'
      ? await admin.auth.admin.generateLink({ type: 'invite', email, options: { data: dados, redirectTo } })
      : await admin.auth.admin.generateLink({ type: 'recovery', email, options: { redirectTo } })

  const tokenHash = data?.properties?.hashed_token
  if (error || !tokenHash || !data?.user?.id) {
    throw error ?? new Error('Link de convite nao gerado')
  }

  return { link: montarLinkConvite(siteUrl, tokenHash, tipo), usuarioId: data.user.id }
}
