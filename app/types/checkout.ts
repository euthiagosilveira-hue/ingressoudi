export type CheckoutStep =
  | 'QUANTIDADE'
  | 'PARTICIPANTES'
  | 'COMPRADOR'
  | 'REVISAO'
  | 'RESERVA_CRIADA'

export interface CheckoutParticipant {
  nome: string
  /** true = meia-entrada (so quando o evento tem meia-entrada ativa). */
  meia?: boolean
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
  meia?: boolean
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
  /** Soma dos ingressos (sem taxa). Ausente no mock DEV. */
  valorIngressos?: number
  taxaServicoUnitaria?: number
  /** true = comprador paga a taxa; false = produtor absorve. */
  taxaRepassada?: boolean
  /** Comissao da plataforma neste pedido. */
  valorTaxaTotal?: number
  /** Quantos ingressos sao meia-entrada. */
  quantidadeMeia?: number
  /** Preco da meia-entrada neste pedido. */
  valorUnitarioMeia?: number
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
  | 'MEIA_INDISPONIVEL'
  | 'DADOS_INVALIDOS'
  | 'ERRO_INESPERADO'
