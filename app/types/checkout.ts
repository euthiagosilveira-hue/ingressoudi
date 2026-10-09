export type CheckoutStep =
  | 'QUANTIDADE'
  | 'PARTICIPANTES'
  | 'COMPRADOR'
  | 'REVISAO'
  | 'RESERVA_CRIADA'

export interface CheckoutParticipant {
  nome: string
}

export interface CheckoutBuyer {
  nome: string
  telefone: string
  email: string
}

export interface CheckoutDraft {
  quantidade: number
  participantes: CheckoutParticipant[]
  comprador: CheckoutBuyer
}

export interface CheckoutReservationTicket {
  id: string
  codigo: string
  participanteNome: string
}

/**
 * Reserva retornada por public.criar_reserva (ou pelo mock DEV).
 * O banco e a fonte de verdade de lote, preco, total, expiracao e codigos.
 */
export interface CheckoutReservation {
  pedidoId: string
  codigoPedido: string
  /** Bearer token do checkout (vem do banco). Null no mock DEV. */
  checkoutToken: string | null
  eventoId: string
  loteId: string
  quantidade: number
  valorUnitario: number
  valorTotal: number
  reservaExpiraEm: string
  status: string
  ingressos: CheckoutReservationTicket[]
}

export interface CheckoutBuyerErrors {
  nome: string
  telefone: string
  email: string
}

/** Origem do evento que o checkout esta usando. */
export type EventoOrigem = 'SUPABASE' | 'MOCK'

export type ReservaErrorCode =
  | 'SEM_ESTOQUE'
  | 'VENDAS_ENCERRADAS'
  | 'EVENTO_CANCELADO'
  | 'EVENTO_INDISPONIVEL'
  | 'SEM_LOTE'
  | 'DADOS_INVALIDOS'
  | 'ERRO_INESPERADO'
