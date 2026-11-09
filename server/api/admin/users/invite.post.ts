import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

const PERFIS = ['ADMINISTRADOR', 'PORTARIA', 'SOCIO']
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const LIMITE_EVENTOS = 200
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
 *        - senao, apenas cria o vinculo (a pessoa entra com a senha que ja tem);
 *   4. senao, gera o LINK de convite via Supabase Auth Admin (generateLink, sem
 *      e-mail), cria public.usuarios e o vinculo em membros_organizacao, e
 *      devolve o link para o administrador enviar (copiar ou WhatsApp);
 *   5. compensa (remove usuario/auth user) se a sincronizacao falhar;
 *   6. registra auditoria na organizacao.
 *   7. SOCIO (Socio do Evento): grava os eventos que ele acompanha
 *      (public.socios_eventos), so eventos da organizacao ativa.
 *
 * Usa service role SOMENTE no backend. Devolve apenas o link do convite.
 */
export default defineEventHandler(async (event) => {
  const claims = await serverSupabaseUser(event).catch(() => null)
  const uid = claims?.sub ? String(claims.sub) : ''
  if (!uid) {
    setResponseStatus(event, 401)
    return { error: 'NAO_AUTENTICADO' }
  }

  const body = await readBody<{ nome?: string; email?: string; perfil?: string; eventos?: unknown }>(
    event
  ).catch(() => ({}))
  const nome = String(body?.nome ?? '').trim()
  const email = String(body?.email ?? '').trim().toLowerCase()
  const perfil = String(body?.perfil ?? '').trim()
  const eventos = Array.isArray(body?.eventos)
    ? [...new Set(body.eventos.map((e) => String(e ?? '').trim()).filter((e) => UUID_RE.test(e)))]
    : []

  if (!nome || nome.length > LIMITE_NOME || !EMAIL_RE.test(email) || !PERFIS.includes(perfil)) {
    setResponseStatus(event, 400)
    return { error: 'DADOS_INVALIDOS' }
  }
  if (perfil === 'SOCIO' && (eventos.length === 0 || eventos.length > LIMITE_EVENTOS)) {
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

  // SOCIO: todos os eventos marcados precisam ser desta organizacao.
  if (perfil === 'SOCIO') {
    const { data: eventosDaCasa, error: erroEventos } = await admin
      .from('eventos')
      .select('id')
      .eq('organizacao_id', organizacaoId)
      .in('id', eventos)
    if (erroEventos || (eventosDaCasa ?? []).length !== eventos.length) {
      setResponseStatus(event, 400)
      return { error: 'DADOS_INVALIDOS' }
    }
  }

  // Grava os eventos do socio; em falha, desfaz o vinculo criado agora.
  async function vincularEventosSocio(usuarioId: string): Promise<boolean> {
    if (perfil !== 'SOCIO') return true
    const { error } = await admin.from('socios_eventos').insert(
      eventos.map((eventoId) => ({
        organizacao_id: organizacaoId,
        usuario_id: usuarioId,
        evento_id: eventoId,
        criado_por: uid
      }))
    )
    return !error
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

    if (!(await vincularEventosSocio(String(existente.id)))) {
      await admin
        .from('membros_organizacao')
        .delete()
        .eq('organizacao_id', organizacaoId)
        .eq('usuario_id', existente.id)
      setResponseStatus(event, 500)
      return { error: 'ERRO_INESPERADO' }
    }

    await admin.from('auditoria').insert({
      usuario_id: uid,
      acao: 'USUARIO_VINCULADO',
      entidade: 'usuarios',
      entidade_id: existente.id,
      dados_novos: { email, perfil, ativo: true, ...(perfil === 'SOCIO' ? { eventos } : {}) },
      organizacao_id: organizacaoId
    })

    // Conta que nunca criou senha e nao pertence a outra organizacao: gera um
    // novo link para a pessoa concluir o cadastro.
    const { data: situacao } = await admin.rpc('situacao_convite_usuario', {
      p_usuario_id: existente.id,
      p_organizacao_id: organizacaoId
    })
    if (situacao?.pendente && Number(situacao.outras_organizacoes) === 0) {
      const tipo = situacao.email_confirmado ? 'recovery' : 'invite'
      const convite = await gerarLinkConvite(admin, { email, tipo, siteUrl: urlDoSite(event) }).catch(() => null)
      if (convite) return { ok: true, link: convite.link }
    }

    return { ok: true, vinculado: true, pendente: Boolean(situacao?.pendente) }
  }

  // 4) novo usuario: link de convite (sem e-mail; o administrador envia o link)
  const siteUrl = urlDoSite(event)
  let convite: { link: string; usuarioId: string }
  try {
    convite = await gerarLinkConvite(admin, { email, tipo: 'invite', siteUrl, dados: { nome, perfil } })
  } catch (erroConvite) {
    const mensagem = String((erroConvite as Error)?.message ?? '').toLowerCase()
    if (mensagem.includes('already') || mensagem.includes('registered') || mensagem.includes('exists')) {
      setResponseStatus(event, 409)
      return { error: 'EMAIL_DUPLICADO', message: 'Já existe um usuário com este e-mail.' }
    }
    setResponseStatus(event, 502)
    return { error: 'FALHA_CONVITE', message: 'Não foi possível gerar o convite.' }
  }

  const novoUsuarioId = convite.usuarioId

  const { error: erroSync } = await admin
    .from('usuarios')
    .upsert({ id: novoUsuarioId, nome, email, perfil, ativo: true }, { onConflict: 'id' })

  // o vinculo define a organizacao ativa do novo usuario (trigger no banco)
  const { error: erroMembro } = erroSync
    ? { error: erroSync }
    : await admin
        .from('membros_organizacao')
        .insert({ organizacao_id: organizacaoId, usuario_id: novoUsuarioId, perfil, ativo: true })

  const erroEventosSocio =
    !erroSync && !erroMembro && !(await vincularEventosSocio(novoUsuarioId))
      ? { code: '', message: 'eventos do socio' }
      : null

  if (erroSync || erroMembro || erroEventosSocio) {
    // Compensacao: evita auth.users/usuarios orfaos.
    if (!erroMembro && !erroSync) {
      await admin
        .from('membros_organizacao')
        .delete()
        .eq('organizacao_id', organizacaoId)
        .eq('usuario_id', novoUsuarioId)
    }
    if (!erroSync) await admin.from('usuarios').delete().eq('id', novoUsuarioId)
    await admin.auth.admin.deleteUser(novoUsuarioId).catch(() => {})
    const erro = erroSync ?? erroMembro ?? erroEventosSocio
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
    dados_novos: {
      nome,
      email,
      perfil,
      ativo: true,
      convite: 'link',
      ...(perfil === 'SOCIO' ? { eventos } : {})
    },
    organizacao_id: organizacaoId
  })

  return { ok: true, link: convite.link }
})
