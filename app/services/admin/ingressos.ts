import type {
  AdminTicketDetailRow,
  AdminTicketRow,
  TicketStatus
} from '~/types/ingresso'

export interface AdminTicketFiltros {
  eventoId?: string | null
  pedidoId?: string | null
  busca?: string | null
  status?: TicketStatus | null
}

/** Listagem administrativa real de ingressos (RPC segura, ADMINISTRADOR). */
export async function listarIngressosAdmin(
  filtros: AdminTicketFiltros = {}
): Promise<AdminTicketRow[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_ingressos_admin', {
    p_evento_id: filtros.eventoId ?? null,
    p_pedido_id: filtros.pedidoId ?? null,
    p_busca: filtros.busca?.trim() ? filtros.busca.trim() : null,
    p_status: filtros.status ?? null
  })
  if (error) {
    throw new Error('Não foi possível carregar os ingressos.')
  }
  return (data ?? []) as AdminTicketRow[]
}

/** Detalhe administrativo real de ingresso (RPC segura, ADMINISTRADOR). */
export async function obterIngressoAdmin(
  ingressoId: string
): Promise<AdminTicketDetailRow | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_ingresso_admin', {
    p_ingresso_id: ingressoId
  })
  if (error) {
    throw new Error('Não foi possível carregar o ingresso.')
  }
  return (data as AdminTicketDetailRow | null) ?? null
}
