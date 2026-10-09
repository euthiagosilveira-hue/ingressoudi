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
