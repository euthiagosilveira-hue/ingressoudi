import type { OrderStatus } from '~/types/pedido'

/** Estados de ingresso relevantes para exibicao publica pos-pagamento. */
export type PublicTicketStatus = 'VALIDO' | 'UTILIZADO' | 'CANCELADO' | 'EXPIRADO'

/** Ingresso individual exibido ao comprador. qr_token so vem se utilizavel. */
export interface PublicTicket {
  ingressoId: string
  codigo: string
  participanteNome: string
  status: PublicTicketStatus
  qrToken: string | null
  utilizadoEm: string | null
}

/** Retorno de public.obter_ingressos_checkout (dados seguros do pedido). */
export interface PublicOrderTickets {
  pedidoId: string
  codigoPedido: string
  eventoId: string
  eventoSlug: string
  eventoNome: string
  eventoInicioEm: string
  eventoLocal: string
  eventoEndereco: string
  pedidoStatus: OrderStatus
  /** true somente com pedido PAGO e pagamento APROVADO. */
  disponivel: boolean
  ingressos: PublicTicket[]
}

export type TicketsErrorCode = 'CHECKOUT_INVALIDO' | 'ERRO_INESPERADO'
