import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

const PERFIS = ['ADMINISTRADOR', 'PORTARIA']
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const LIMITE_NOME = 120

/**
 * Convida um usuario para a ORGANIZACAO ATIVA de quem convida (multiempresa).
 *
 * Fluxo:
 *   1. valida sessao do solicitante;
 *   2. valida que o solicitante e ADMINISTRADOR ativo da sua organizacao ativa
 *      (membro ativo, organizacao ativa) — via service role;
 *   3. se o e-mail JA tem conta no Ingressoudi:
 *        - ja e membro desta organizacao -> 409;
 *        - senao, apenas cria o vinculo (sem novo convite por e-mail);
 *   4. senao, envia convite oficial via Supabase Auth Admin, cria public.usuarios
 *      e o vinculo em membros_organizacao;
 *   5. compensa (remove usuario/auth user) se a sincronizacao falhar;
 *   6. registra auditoria na organizacao.
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

  // 2) solicitante: usuario ativo + ADMINISTRADOR ativo da organizacao ativa
  const { data: solicitante, error: erroSolicitante } = await admin
    .from('usuarios')
    .select('ativo,organizacao_ativa_id')
    .eq('id', uid)
    .maybeSingle()

  if (erroSolicitante) {
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }
  const organizacaoId = solicitante?.organizacao_ativa_id ? String(solicitante.organizacao_ativa_id) : ''
  if (!solicitante?.ativo || !organizacaoId) {
    setResponseStatus(event, 403)
    return { error: 'SEM_PERMISSAO' }
  }

  const [{ data: membroSolicitante }, { data: organizacao }] = await Promise.all([
    admin
      .from('membros_organizacao')
      .select('perfil,ativo')
      .eq('organizacao_id', organizacaoId)
      .eq('usuario_id', uid)
      .maybeSingle(),
    admin.from('organizacoes').select('id,ativo').eq('id', organizacaoId).maybeSingle()
  ])

  if (!organizacao?.ativo || !membroSolicitante?.ativo || membroSolicitante.perfil !== 'ADMINISTRADOR') {
    setResponseStatus(event, 403)
    return { error: 'SEM_PERMISSAO' }
  }

  // 3) e-mail ja cadastrado na plataforma?
  const { data: existente } = await admin
    .from('usuarios')
    .select('id')
    .ilike('email', email)
    .maybeSingle()

  if (existente) {
    const { data: jaMembro } = await admin
      .from('membros_organizacao')
      .select('usuario_id')
      .eq('organizacao_id', organizacaoId)
      .eq('usuario_id', existente.id)
      .maybeSingle()

    if (jaMembro) {
      setResponseStatus(event, 409)
      return { error: 'EMAIL_DUPLICADO', message: 'Este usuário já faz parte da sua organização.' }
    }

    const { error: erroVinculo } = await admin
      .from('membros_organizacao')
      .insert({ organizacao_id: organizacaoId, usuario_id: existente.id, perfil, ativo: true })

    if (erroVinculo) {
      setResponseStatus(event, 500)
      return { error: 'ERRO_INESPERADO' }
    }

    await admin.from('auditoria').insert({
      usuario_id: uid,
      acao: 'USUARIO_VINCULADO',
      entidade: 'usuarios',
      entidade_id: existente.id,
      dados_novos: { email, perfil, ativo: true },
      organizacao_id: organizacaoId
    })

    return { ok: true, vinculado: true }
  }

  // 4) novo usuario: convite oficial
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
    .upsert({ id: novoUsuarioId, nome, email, perfil, ativo: true }, { onConflict: 'id' })

  // o vinculo define a organizacao ativa do novo usuario (trigger no banco)
  const { error: erroMembro } = erroSync
    ? { error: erroSync }
    : await admin
        .from('membros_organizacao')
        .insert({ organizacao_id: organizacaoId, usuario_id: novoUsuarioId, perfil, ativo: true })

  if (erroSync || erroMembro) {
    // Compensacao: evita auth.users/usuarios orfaos.
    if (!erroSync) await admin.from('usuarios').delete().eq('id', novoUsuarioId)
    await admin.auth.admin.deleteUser(novoUsuarioId).catch(() => {})
    const erro = erroSync ?? erroMembro
    const mensagem = (erro?.message ?? '').toLowerCase()
    if (erro?.code === '23505' || mensagem.includes('duplicate') || mensagem.includes('unique')) {
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
    dados_novos: { nome, email, perfil, ativo: true },
    organizacao_id: organizacaoId
  })

  return { ok: true }
})
