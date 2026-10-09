import type { OrderTicket } from '~/types/ingresso'
import type { OrderPayment, PaymentProvider } from '~/types/pagamento'

export type OrderStatus = 'RESERVADO' | 'PAGO' | 'EXPIRADO' | 'CANCELADO'

export type OrderPriceType = 'LOTE' | 'AVULSO'

export interface OrderListItem {
  id: string
  codigo: string
  eventoId: string
  eventoNome: string
  loteId: string | null
  loteNome: string | null
  compradorNome: string
  telefone: string
  email: string | null
  quantidade: number
  tipoPreco: OrderPriceType
  valorUnitario: number
  valorTotal: number
  status: OrderStatus
  reservaExpiraEm: string | null
  pagoEm: string | null
  canceladoEm: string | null
  criadoEm: string
  pagamentoProvedor: PaymentProvider | null
}

export type OrderStatusFilter = 'TODOS' | OrderStatus

export type OrderPriceTypeFilter = 'TODOS' | OrderPriceType

export interface OrderFiltersState {
  busca: string
  eventoId: string
  status: OrderStatusFilter
  tipoPreco: OrderPriceTypeFilter
}

export type OrderSort = 'RECENTES' | 'ANTIGOS'

export interface OrderSummaryData {
  total: number
  pagos: number
  reservados: number
  expirados: number
  cancelados: number
  valorPago: number
}

export type OrderHistoryType =
  | 'PEDIDO_CRIADO'
  | 'RESERVA_CRIADA'
  | 'PAGAMENTO_INICIADO'
  | 'PAGAMENTO_APROVADO'
  | 'INGRESSOS_LIBERADOS'
  | 'PEDIDO_EXPIRADO'
  | 'PEDIDO_CANCELADO'
  | 'REEMBOLSO_SOLICITADO'
  | 'REEMBOLSO_CONCLUIDO'

export interface OrderHistoryEvent {
  id: string
  tipo: OrderHistoryType
  titulo: string
  descricao?: string | null
  ocorridoEm: string
}

export interface OrderDetail extends OrderListItem {
  atualizadoEm: string | null
  eventoInicioEm: string | null
  eventoLocal: string | null
  motivoValorAvulso: string | null
  autorizadoPorUsuarioId: string | null
  autorizadoPorNome: string | null
  pagamento: OrderPayment | null
  ingressos: OrderTicket[]
  historico: OrderHistoryEvent[]
}

/** Linha bruta de public.listar_pedidos_admin. */
export interface AdminPedidoRow {
  id: string
  codigo: string
  evento_id: string
  evento_nome: string
  lote_id: string | null
  lote_nome: string | null
  comprador_nome: string
  comprador_telefone: string
  comprador_email: string | null
  quantidade: number
  tipo_preco: string
  valor_unitario: number | string
  valor_total: number | string
  status: string
  reserva_expira_em: string | null
  pago_em: string | null
  cancelado_em: string | null
  criado_em: string
  atualizado_em: string | null
  motivo_valor_avulso: string | null
  autorizado_por_nome: string | null
  pagamento_status: string | null
  pagamento_valor: number | string | null
  pagamento_provedor: string | null
}

export interface AdminPedidoPagamentoRaw {
  id: string
  status: string
  valor: number | string
  provedor: string
  transacao_id: string | null
  cobranca_id: string | null
  referencia_externa: string | null
  expira_em: string | null
  confirmado_em: string | null
  cancelado_em: string | null
  reembolsado_em: string | null
  valor_reembolsado: number | string | null
}

export interface AdminPedidoIngressoRaw {
  id: string
  codigo: string
  participante_nome: string
  valor_unitario: number | string
  status: string
  utilizado_em: string | null
}

export interface AdminPedidoDetalheRow extends AdminPedidoRow {
  evento_inicio_em: string | null
  evento_local: string | null
  pagamento: AdminPedidoPagamentoRaw | null
  ingressos: AdminPedidoIngressoRaw[] | null
}
