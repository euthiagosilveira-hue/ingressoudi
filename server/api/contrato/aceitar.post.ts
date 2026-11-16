import { getRequestIP } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

/**
 * Registra o aceite do Contrato do Organizador pela casa ativa.
 *
 * Regras:
 *   - solicitante: ADMINISTRADOR ativo (membro) da organizacao ativa; o super
 *     admin em modo suporte NAO aceita pelo produtor;
 *   - a versao enviada precisa ser a vigente (o banco confere);
 *   - os dados do organizador precisam estar completos (o banco confere).
 *
 * O IP e o navegador vem do servidor (nao do navegador), e o registro e
 * gravado com service role em public.aceites_contrato_organizador.
 */
export default defineEventHandler(async (event) => {
  if (!limitar(event, 10)) {
    setResponseStatus(event, 429)
    return { error: 'MUITAS_TENTATIVAS' }
  }

  const { usuarioId, organizacaoId } = await exigirAdminOrganizacaoAtiva(event)

  const body = await readBody<{ versao?: string }>(event).catch(() => ({}))
  const versao = String(body?.versao ?? '').trim().slice(0, 40)
  if (!versao) {
    setResponseStatus(event, 400)
    return { error: 'DADOS_INVALIDOS' }
  }

  const ip = getRequestIP(event, { xForwardedFor: true }) ?? null
  const userAgent = getRequestHeader(event, 'user-agent') ?? null

  const admin = serverSupabaseServiceRole(event)
  const { data, error } = await admin.rpc('registrar_aceite_contrato', {
    p_usuario_id: usuarioId,
    p_organizacao_id: organizacaoId,
    p_versao: versao,
    p_ip: ip,
    p_user_agent: userAgent
  })

  if (error) {
    const msg = String(error.message ?? '').toLowerCase()
    if (msg.includes('desatualizada')) {
      setResponseStatus(event, 409)
      return { error: 'VERSAO_DESATUALIZADA' }
    }
    if (msg.includes('complete os dados')) {
      setResponseStatus(event, 409)
      return { error: 'DADOS_INCOMPLETOS' }
    }
    if (msg.includes('administrador')) {
      setResponseStatus(event, 403)
      return { error: 'SEM_PERMISSAO' }
    }
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }

  const r = (data ?? {}) as { aceito_em?: string; versao?: string }
  return { ok: true, aceitoEm: r.aceito_em ?? null, versao: r.versao ?? versao }
})
