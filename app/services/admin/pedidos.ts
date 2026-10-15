import type {
  AdminPedidoDetalheRow,
  AdminPedidoRow,
  OrderPriceType,
  OrderStatus
} from '~/types/pedido'
import type { PaymentStatus } from '~/types/pagamento'

export interface AdminPedidoFiltros {
  eventoId?: string | null
  busca?: string | null
  status?: OrderStatus | null
  pagamentoStatus?: PaymentStatus | null
  tipoPreco?: OrderPriceType | null
  de?: string | null
  ate?: string | null
}

/** Listagem administrativa real de pedidos (RPC segura, ADMINISTRADOR). */
export async function listarPedidosAdmin(
  filtros: AdminPedidoFiltros = {}
): Promise<AdminPedidoRow[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_pedidos_admin', {
    p_evento_id: filtros.eventoId ?? null,
    p_busca: filtros.busca?.trim() ? filtros.busca.trim() : null,
    p_status: filtros.status ?? null,
    p_pagamento_status: filtros.pagamentoStatus ?? null,
    p_tipo_preco: filtros.tipoPreco ?? null,
    p_de: filtros.de ?? null,
    p_ate: filtros.ate ?? null
  })
  if (error) {
    throw new Error('Não foi possível carregar os pedidos.')
  }
  return (data ?? []) as AdminPedidoRow[]
}

export interface ResultadoReembolso {
  valor: number
  manual: boolean
  emProcesso: boolean
}

/**
 * Reembolso total do pedido (ingressos + taxa). Pix: estorno na conta Mercado
 * Pago da casa. Dinheiro: apenas registra a devolucao. Cancela os ingressos.
 */
export async function reembolsarPedido(pedidoId: string, motivo: string): Promise<ResultadoReembolso> {
  try {
    const r = await $fetch<{ ok: boolean; valor?: number; manual?: boolean; emProcesso?: boolean; mensagem?: string }>(
      `/api/admin/pedidos/${encodeURIComponent(pedidoId)}/reembolso`,
      { method: 'POST', body: { motivo } }
    )
    if (!r?.ok) throw new Error(r?.mensagem ?? 'Não foi possível concluir o reembolso.')
    return { valor: Number(r.valor ?? 0), manual: Boolean(r.manual), emProcesso: Boolean(r.emProcesso) }
  } catch (e) {
    const erro = e as Error & { data?: { mensagem?: string; statusMessage?: string } }
    if (erro?.data?.mensagem) throw new Error(erro.data.mensagem)
    if (erro?.data?.statusMessage === 'SEM_PERMISSAO') throw new Error('Você não tem permissão para reembolsar pedidos.')
    throw new Error(erro instanceof Error && erro.message && !erro.data ? erro.message : 'Não foi possível concluir o reembolso.')
  }
}

/** Detalhe administrativo real de pedido (RPC segura, ADMINISTRADOR). */
export async function obterPedidoAdmin(
  pedidoId: string
): Promise<AdminPedidoDetalheRow | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_pedido_admin', { p_pedido_id: pedidoId })
  if (error) {
    throw new Error('Não foi possível carregar o pedido.')
  }
  return (data as AdminPedidoDetalheRow | null) ?? null
}
