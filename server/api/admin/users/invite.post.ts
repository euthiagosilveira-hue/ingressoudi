import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

const PERFIS = ['ADMINISTRADOR', 'PORTARIA']
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const LIMITE_NOME = 120

/**
 * Convida um novo usuario (ADMINISTRADOR ativo).
 *
 * Fluxo:
 *   1. valida sessao do solicitante;
 *   2. valida que o solicitante e ADMINISTRADOR ativo (via service role);
 *   3. rejeita e-mail duplicado;
 *   4. envia convite oficial via Supabase Auth Admin;
 *   5. sincroniza public.usuarios (upsert por id);
 *   6. compensa removendo o auth user se a sync falhar (sem estado parcial);
 *   7. registra auditoria.
 *
 * Usa service role SOMENTE no backend. Nunca devolve chaves/tokens.
 */
export default defineEventHandler(async (event) => {
  const claims = await serverSupabaseUser(event).catch(() => null)
  const uid = claims?.sub ? String(claims.sub) : ''
  if (!uid) {
    setResponseStatus(event, 401)
    return { error: 'NAO_AUTENTICADO' }
  }

  const body = await readBody<{ nome?: string; email?: string; perfil?: string }>(event).catch(
    () => ({})
  )
  const nome = String(body?.nome ?? '').trim()
  const email = String(body?.email ?? '').trim().toLowerCase()
  const perfil = String(body?.perfil ?? '').trim()

  if (!nome || nome.length > LIMITE_NOME || !EMAIL_RE.test(email) || !PERFIS.includes(perfil)) {
    setResponseStatus(event, 400)
    return { error: 'DADOS_INVALIDOS' }
  }

  const admin = serverSupabaseServiceRole(event)

  const { data: solicitante, error: erroSolicitante } = await admin
    .from('usuarios')
    .select('perfil,ativo')
    .eq('id', uid)
    .maybeSingle()

  if (erroSolicitante) {
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }
  if (!solicitante?.ativo || solicitante.perfil !== 'ADMINISTRADOR') {
    setResponseStatus(event, 403)
    return { error: 'SEM_PERMISSAO' }
  }

  const { data: existente } = await admin
    .from('usuarios')
    .select('id')
    .ilike('email', email)
    .maybeSingle()

  if (existente) {
    setResponseStatus(event, 409)
    return { error: 'EMAIL_DUPLICADO', message: 'Já existe um usuário com este e-mail.' }
  }

  // URL publica canonica (NUXT_PUBLIC_SITE_URL). Evita depender de
  // getRequestURL().origin, que pode resolver localhost/host interno atras de proxy.
  const config = useRuntimeConfig(event)
  const siteUrl = String(config.public.siteUrl || getRequestURL(event).origin).replace(/\/+$/, '')
  const { data: convite, error: erroConvite } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { nome, perfil },
    redirectTo: `${siteUrl}/auth/convite`
  })

  if (erroConvite || !convite?.user) {
    const mensagem = (erroConvite?.message ?? '').toLowerCase()
    if (mensagem.includes('already') || mensagem.includes('registered') || mensagem.includes('exists')) {
      setResponseStatus(event, 409)
      return { error: 'EMAIL_DUPLICADO', message: 'Já existe um usuário com este e-mail.' }
    }
    setResponseStatus(event, 502)
    return { error: 'FALHA_CONVITE', message: 'Não foi possível enviar o convite.' }
  }

  const novoUsuarioId = convite.user.id

  const { error: erroSync } = await admin
    .from('usuarios')
    .upsert(
      { id: novoUsuarioId, nome, email, perfil, ativo: true },
      { onConflict: 'id' }
    )

  if (erroSync) {
    // Compensacao: evita auth.users orfao (sem public.usuarios).
    await admin.auth.admin.deleteUser(novoUsuarioId).catch(() => {})
    const mensagem = (erroSync.message ?? '').toLowerCase()
    if (
      erroSync.code === '23505' ||
      mensagem.includes('duplicate') ||
      mensagem.includes('unique')
    ) {
      setResponseStatus(event, 409)
      return { error: 'EMAIL_DUPLICADO', message: 'Já existe um usuário com este e-mail.' }
    }
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }

  await admin.from('auditoria').insert({
    usuario_id: uid,
    acao: 'USUARIO_CRIADO',
    entidade: 'usuarios',
    entidade_id: novoUsuarioId,
    dados_novos: { nome, email, perfil, ativo: true }
  })

  return { ok: true }
})
