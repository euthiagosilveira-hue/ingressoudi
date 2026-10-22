import type { H3Event } from 'h3'

import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

export interface AdminOrganizacao {
  usuarioId: string
  organizacaoId: string
}

/**
 * Exige sessao de um ADMINISTRADOR ativo da organizacao ativa (membro ativo,
 * organizacao ativa). Mesma regra do convite de usuarios. Lanca erro HTTP
 * 401/403 caso contrario. Usa service role somente no backend.
 * Com `permitirSuporte`, aceita tambem o super admin em modo suporte (casa da
 * qual nao e membro); Mercado Pago e convites nao usam essa opcao.
 */
export async function exigirAdminOrganizacaoAtiva(
  event: H3Event,
  opcoes: { permitirSuporte?: boolean } = {}
): Promise<AdminOrganizacao> {
  const claims = await serverSupabaseUser(event).catch(() => null)
  const usuarioId = claims?.sub ? String(claims.sub) : ''
  if (!usuarioId) {
    throw createError({ statusCode: 401, statusMessage: 'NAO_AUTENTICADO' })
  }

  const admin = serverSupabaseServiceRole(event)
  const { data: usuario, error } = await admin
    .from('usuarios')
    .select('ativo,organizacao_ativa_id,super_admin')
    .eq('id', usuarioId)
    .maybeSingle()

  if (error) throw createError({ statusCode: 500, statusMessage: 'ERRO_INESPERADO' })

  const organizacaoId = usuario?.organizacao_ativa_id ? String(usuario.organizacao_ativa_id) : ''
  if (!usuario?.ativo || !organizacaoId) {
    throw createError({ statusCode: 403, statusMessage: 'SEM_PERMISSAO' })
  }

  const [{ data: membro }, { data: organizacao }] = await Promise.all([
    admin
      .from('membros_organizacao')
      .select('perfil,ativo')
      .eq('organizacao_id', organizacaoId)
      .eq('usuario_id', usuarioId)
      .maybeSingle(),
    admin.from('organizacoes').select('id,ativo').eq('id', organizacaoId).maybeSingle()
  ])

  const adminMembro = Boolean(membro?.ativo && membro.perfil === 'ADMINISTRADOR')
  const suporte = Boolean(opcoes.permitirSuporte && usuario.super_admin === true && !membro?.ativo)
  if (!organizacao?.ativo || !(adminMembro || suporte)) {
    throw createError({ statusCode: 403, statusMessage: 'SEM_PERMISSAO' })
  }

  return { usuarioId, organizacaoId }
}
