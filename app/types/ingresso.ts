import type { OrderPriceType, OrderStatus } from '~/types/pedido'

export type TicketStatus =
  | 'RESERVADO'
  | 'VALIDO'
  | 'UTILIZADO'
  | 'EXPIRADO'
  | 'CANCELADO'

export interface OrderTicket {
  id: string
  codigo: string
  participanteNome: string
  valorUnitario: number
  status: TicketStatus
  utilizadoEm: string | null
}

export interface TicketListItem extends OrderTicket {
  pedidoId: string
  pedidoCodigo: string
  eventoId: string
  eventoNome: string
  loteId: string | null
  loteNome: string | null
  criadoEm: string
}

export type TicketStatusFilter = 'TODOS' | TicketStatus

export interface TicketFiltersState {
  busca: string
  eventoId: string
  status: TicketStatusFilter
}

export type TicketSort = 'RECENTES' | 'ANTIGOS' | 'PARTICIPANTE_AZ'

export interface TicketSummaryData {
  total: number
  validos: number
  utilizados: number
  reservados: number
  cancelados: number
  expirados: number
}

export type TicketHistoryType =
  | 'INGRESSO_RESERVADO'
  | 'PAGAMENTO_CONFIRMADO'
  | 'INGRESSO_LIBERADO'
  | 'ENTRADA_REGISTRADA'
  | 'ENTRADA_ANULADA'
  | 'INGRESSO_EXPIRADO'
  | 'INGRESSO_CANCELADO'

export interface TicketHistoryEvent {
  id: string
  tipo: TicketHistoryType
  titulo: string
  descricao?: string | null
  ocorridoEm: string
}

export interface TicketDetail extends TicketListItem {
  pedidoStatus: OrderStatus
  tipoPreco: OrderPriceType
  eventoInicioEm: string | null
  eventoLocal: string | null
  valorPedido: number
  qrMockValue: string
  historico: TicketHistoryEvent[]
}

/** Linha bruta de public.listar_ingressos_admin. */
export interface AdminTicketRow {
  ingresso_id: string
  codigo: string
  participante_nome: string
  status: string
  valor_unitario: number | string
  utilizado_em: string | null
  criado_em: string
  pedido_id: string
  pedido_codigo: string
  evento_id: string
  evento_nome: string
  evento_inicio_em: string | null
  lote_id: string | null
  lote_nome: string | null
}

export interface AdminTicketEntradaRaw {
  entrada_id: string
  entrada_em: string
  metodo: string | null
}

export interface AdminTicketDetailRow extends AdminTicketRow {
  pedido_status: string
  evento_local: string | null
  entrada: AdminTicketEntradaRaw | null
}
