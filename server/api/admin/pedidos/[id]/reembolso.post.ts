import { serverSupabaseServiceRole } from '#supabase/server'

import { ehUuid } from '../../../../services/payments/payment-service'
import { obterAccessTokenOrganizacao } from '../../../../services/payments/mercado-pago/mercado-pago-conexao'
import {
  detalheErroMp,
  erroJaReembolsado,
  mensagemErroReembolsoMp,
  reembolsarPagamentoMp,
  reembolsoAceito
} from '../../../../services/payments/mercado-pago/mercado-pago-reembolso'
import { exigirAdminOrganizacaoAtiva } from '../../../../utils/organizacao-admin'

/**
 * Reembolso total de um pedido pelo ADMINISTRADOR da organizacao ativa.
 *  - Pix (Mercado Pago): estorna na conta conectada da casa (idempotente).
 *  - Dinheiro: apenas registra (a devolucao e feita pelo produtor).
 * Em sucesso o pedido e cancelado e os ingressos deixam de valer na portaria.
 */
export default defineEventHandler(async (event) => {
  const pedidoId = String(getRouterParam(event, 'id') ?? '')
  if (!ehUuid(pedidoId)) {
    throw createError({ statusCode: 400, statusMessage: 'PEDIDO_INVALIDO' })
  }
  const body = await readBody<{ motivo?: string }>(event).catch(() => ({}) as { motivo?: string })
  const motivo = String(body?.motivo ?? '').trim().slice(0, 300)

  const admin = await exigirAdminOrganizacaoAtiva(event)
  const client = serverSupabaseServiceRole(event)

  const { data: preparo, error: erroPreparo } = await client.rpc('preparar_reembolso_pedido', {
    p_pedido_id: pedidoId,
    p_organizacao_id: admin.organizacaoId,
    p_usuario_id: admin.usuarioId,
    p_motivo: motivo
  })
  if (erroPreparo) {
    const m = (erroPreparo.message ?? '').toLowerCase()
    let mensagem = 'Não foi possível iniciar o reembolso.'
    if (m.includes('motivo')) mensagem = 'Informe o motivo do reembolso.'
    else if (m.includes('utilizado')) mensagem = 'Este pedido tem ingresso já utilizado na portaria e não pode ser reembolsado.'
    else if (m.includes('somente pedido pago')) mensagem = 'Somente pedidos pagos podem ser reembolsados.'
    else if (m.includes('nao encontrado')) mensagem = 'Pedido não encontrado.'
    setResponseStatus(event, 422)
    return { ok: false, mensagem }
  }

  const op = preparo as {
    operacao_id: string
    provedor: string
    transacao_id: string | null
    valor: number | string
  }

  // Venda em dinheiro: nada a estornar no provedor.
  if (op.provedor !== 'MERCADO_PAGO') {
    await client.rpc('concluir_reembolso_pedido', {
      p_operacao_id: op.operacao_id,
      p_organizacao_id: admin.organizacaoId,
      p_sucesso: true,
      p_reembolso_externo_id: null,
      p_observacao: 'Devolução registrada pelo produtor (venda sem Pix).'
    })
    return { ok: true, valor: Number(op.valor), manual: true }
  }

  const falhar = async (mensagem: string, status = 502) => {
    await client.rpc('concluir_reembolso_pedido', {
      p_operacao_id: op.operacao_id,
      p_organizacao_id: admin.organizacaoId,
      p_sucesso: false,
      p_reembolso_externo_id: null,
      p_observacao: mensagem
    })
    setResponseStatus(event, status)
    return { ok: false, mensagem }
  }

  if (!op.transacao_id) {
    return falhar('Pagamento sem identificação no Mercado Pago. Faça a devolução pelo painel do Mercado Pago.', 422)
  }

  let accessToken: string | null = null
  try {
    accessToken = await obterAccessTokenOrganizacao(event, admin.organizacaoId)
  } catch {
    accessToken = null
  }
  if (!accessToken) {
    return falhar('A conta Mercado Pago da casa não está conectada. Conecte em Configurações → Mercado Pago.', 422)
  }

  try {
    const refund = await reembolsarPagamentoMp(accessToken, op.transacao_id, op.operacao_id)
    if (!reembolsoAceito(refund)) {
      return falhar('O Mercado Pago recusou o reembolso. Tente novamente ou faça pelo painel do Mercado Pago.')
    }
    const emProcesso = String(refund.status ?? '').toLowerCase() !== 'approved' && refund.status != null
    await client.rpc('concluir_reembolso_pedido', {
      p_operacao_id: op.operacao_id,
      p_organizacao_id: admin.organizacaoId,
      p_sucesso: true,
      p_reembolso_externo_id: refund.id !== undefined && refund.id !== null ? String(refund.id) : null,
      p_observacao: emProcesso ? 'Reembolso em processamento no Mercado Pago.' : null
    })
    return { ok: true, valor: Number(op.valor), emProcesso }
  } catch (erro) {
    // Tentativa repetida apos um estorno que ja aconteceu: conclui no sistema.
    if (erroJaReembolsado(erro)) {
      await client.rpc('concluir_reembolso_pedido', {
        p_operacao_id: op.operacao_id,
        p_organizacao_id: admin.organizacaoId,
        p_sucesso: true,
        p_reembolso_externo_id: null,
        p_observacao: 'Pagamento já estava reembolsado no Mercado Pago.'
      })
      return { ok: true, valor: Number(op.valor) }
    }
    console.error('[mercado-pago] reembolso falhou', {
      pedidoId,
      organizacaoId: admin.organizacaoId,
      status: (erro as { status?: number })?.status ?? null,
      requestId: (erro as { requestId?: string | null })?.requestId ?? null,
      transacaoId: op.transacao_id,
      detalhe: detalheErroMp(erro)
    })
    return falhar(mensagemErroReembolsoMp(erro))
  }
})
