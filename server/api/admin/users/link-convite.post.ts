import { serverSupabaseServiceRole } from '#supabase/server'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Gera um NOVO link de convite para um membro da organizacao ativa que ainda
 * nao criou a senha (convite pendente). O link anterior deixa de valer.
 *
 * Regras:
 *   - solicitante: ADMINISTRADOR ativo da organizacao ativa;
 *   - alvo: membro desta organizacao, ainda sem senha e sem vinculo com outra
 *     organizacao (um link de acesso nunca e gerado para conta ja em uso).
 *
 * Usa service role SOMENTE no backend. Devolve apenas o link.
 */
export default defineEventHandler(async (event) => {
  if (!limitar(event, 20)) {
    setResponseStatus(event, 429)
    return { error: 'MUITAS_TENTATIVAS' }
  }

  const { usuarioId: solicitanteId, organizacaoId } = await exigirAdminOrganizacaoAtiva(event)

  const body = await readBody<{ usuarioId?: string }>(event).catch(() => ({}))
  const usuarioId = String(body?.usuarioId ?? '').trim()
  if (!UUID_RE.test(usuarioId)) {
    setResponseStatus(event, 400)
    return { error: 'DADOS_INVALIDOS' }
  }

  const admin = serverSupabaseServiceRole(event)
  const { data: situacao, error: erroSituacao } = await admin.rpc('situacao_convite_usuario', {
    p_usuario_id: usuarioId,
    p_organizacao_id: organizacaoId
  })

  if (erroSituacao) {
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }
  if (!situacao?.existe || !situacao.membro) {
    setResponseStatus(event, 404)
    return { error: 'USUARIO_NAO_ENCONTRADO' }
  }
  if (!situacao.pendente) {
    setResponseStatus(event, 409)
    return { error: 'CONVITE_JA_ACEITO' }
  }
  if (Number(situacao.outras_organizacoes) > 0) {
    setResponseStatus(event, 409)
    return { error: 'CONVITE_DE_OUTRA_ORGANIZACAO' }
  }

  const { data: usuario } = await admin.from('usuarios').select('email').eq('id', usuarioId).maybeSingle()
  const email = String(usuario?.email ?? '').trim().toLowerCase()
  if (!email) {
    setResponseStatus(event, 404)
    return { error: 'USUARIO_NAO_ENCONTRADO' }
  }

  // Ainda nao confirmou o e-mail: novo convite. Ja abriu um link antes mas nao
  // criou a senha: link de definicao de senha (recovery).
  const tipo = situacao.email_confirmado ? 'recovery' : 'invite'
  let link = ''
  try {
    link = (await gerarLinkConvite(admin, { email, tipo, siteUrl: urlDoSite(event) })).link
  } catch {
    setResponseStatus(event, 502)
    return { error: 'FALHA_CONVITE' }
  }

  await admin.from('auditoria').insert({
    usuario_id: solicitanteId,
    acao: 'CONVITE_LINK_GERADO',
    entidade: 'usuarios',
    entidade_id: usuarioId,
    dados_novos: { email, tipo },
    organizacao_id: organizacaoId
  })

  return { ok: true, link }
})
