import { serverSupabaseServiceRole, serverSupabaseUser } from '#supabase/server'

import { ehUuid } from '../../services/payments/payment-service'
import { enviarPush, type AssinaturaPush } from '../../utils/push'
import { avisoNovaOrganizacao } from '../../utils/push-mensagens'

/**
 * Chamado pelo cadastro do produtor logo depois de criar a casa. Avisa os
 * super admins por notificacao push uma unica vez por casa. Quem chama precisa
 * estar logado e ser membro da casa informada.
 */
export default defineEventHandler(async (event) => {
  const body = await readBody<{ organizacaoId?: string }>(event).catch(() => ({}) as { organizacaoId?: string })
  const organizacaoId = String(body?.organizacaoId ?? '')
  if (!ehUuid(organizacaoId)) {
    throw createError({ statusCode: 400, statusMessage: 'ORGANIZACAO_INVALIDA' })
  }

  const claims = await serverSupabaseUser(event).catch(() => null)
  const usuarioId = claims?.sub ? String(claims.sub) : ''
  if (!usuarioId) {
    throw createError({ statusCode: 401, statusMessage: 'NAO_AUTENTICADO' })
  }

  const client = serverSupabaseServiceRole(event)
  const { data: membro } = await client
    .from('membros_organizacao')
    .select('ativo')
    .eq('organizacao_id', organizacaoId)
    .eq('usuario_id', usuarioId)
    .maybeSingle()
  if (!membro?.ativo) {
    throw createError({ statusCode: 403, statusMessage: 'SEM_PERMISSAO' })
  }

  const { data, error } = await client.rpc('reservar_aviso_nova_organizacao', { p_organizacao_id: organizacaoId })
  if (error) throw createError({ statusCode: 500, statusMessage: 'ERRO_INESPERADO' })

  const reserva = (data ?? {}) as { enviar?: boolean; nome?: string; aprovada?: boolean; assinaturas?: AssinaturaPush[] }
  if (!reserva.enviar) return { ok: true, enviados: 0 }

  const { enviados, expirados } = await enviarPush(
    reserva.assinaturas ?? [],
    avisoNovaOrganizacao(String(reserva.nome ?? ''), Boolean(reserva.aprovada))
  )
  if (expirados.length) {
    await client.from('push_assinaturas').delete().in('endpoint', expirados)
  }
  return { ok: true, enviados }
})
