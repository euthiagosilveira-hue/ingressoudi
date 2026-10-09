import type { PaymentProvider, PaymentStatus } from '~/types/pagamento'
import type { OrderStatus } from '~/types/pedido'

export interface CheckoutPublicoPagamento {
  pagamentoId: string
  provedor: PaymentProvider
  status: PaymentStatus
  valor: number
  expiraEm: string | null
  transacaoId: string | null
  cobrancaId: string | null
  referenciaExterna: string | null
}

/** Retorno de public.obter_checkout_pedido (somente dados seguros de checkout). */
export interface CheckoutPublico {
  pedidoId: string
  codigoPedido: string
  eventoId: string
  eventoSlug: string
  eventoNome: string
  loteId: string | null
  loteNome: string | null
  quantidade: number
  valorUnitario: number
  valorTotal: number
  pedidoStatus: OrderStatus
  reservaExpiraEm: string
  pagamento: CheckoutPublicoPagamento | null
}

export type PagamentoErrorCode =
  | 'CHECKOUT_INVALIDO'
  | 'RESERVA_EXPIRADA'
  | 'PEDIDO_INDISPONIVEL'
  | 'PAGAMENTO_INDISPONIVEL'
  | 'ERRO_INESPERADO'

export type PagamentoEstado =
  | 'CARREGANDO'
  | 'ERRO'
  | 'NAO_ENCONTRADO'
  | 'PENDENTE'
  | 'EXPIRADO'
  | 'PAGO'
  | 'CANCELADO'
  | 'REJEITADO'
  | 'REEMBOLSADO'
