import type { PaymentProvider, PaymentStatus } from '~/types/pagamento'
import type { OrderStatus } from '~/types/pedido'
import type {
  CheckoutPublico,
  CheckoutPublicoPagamento,
  PagamentoErrorCode
} from '~/types/checkoutPagamento'

interface CheckoutRpcPagamento {
  pagamento_id: string
  provedor: string
  status: string
  valor: number | string
  expira_em: string | null
  transacao_id: string | null
  cobranca_id: string | null
  referencia_externa: string | null
}

interface CheckoutRpcRow {
  pedido_id: string
  codigo_pedido: string
  evento_id: string
  evento_slug: string
  evento_nome: string
  lote_id: string | null
  lote_nome: string | null
  quantidade: number
  valor_unitario: number | string
  valor_total: number | string
  pedido_status: string
  reserva_expira_em: string
  pagamento: CheckoutRpcPagamento | null
}

interface RpcErrorLike {
  message?: string | null
  code?: string | null
}

export class PagamentoError extends Error {
  code: PagamentoErrorCode

  constructor(code: PagamentoErrorCode, message: string) {
    super(message)
    this.name = 'PagamentoError'
    this.code = code
  }
}

function mapearPagamento(row: CheckoutRpcPagamento): CheckoutPublicoPagamento {
  return {
    pagamentoId: row.pagamento_id,
    provedor: row.provedor as PaymentProvider,
    status: row.status as PaymentStatus,
    valor: Number(row.valor),
    expiraEm: row.expira_em,
    transacaoId: row.transacao_id,
    cobrancaId: row.cobranca_id,
    referenciaExterna: row.referencia_externa
  }
}

function mapearCheckout(row: CheckoutRpcRow): CheckoutPublico {
  return {
    pedidoId: row.pedido_id,
    codigoPedido: row.codigo_pedido,
    eventoId: row.evento_id,
    eventoSlug: row.evento_slug,
    eventoNome: row.evento_nome,
    loteId: row.lote_id,
    loteNome: row.lote_nome,
    quantidade: Number(row.quantidade),
    valorUnitario: Number(row.valor_unitario),
    valorTotal: Number(row.valor_total),
    pedidoStatus: row.pedido_status as OrderStatus,
    reservaExpiraEm: row.reserva_expira_em,
    pagamento: row.pagamento ? mapearPagamento(row.pagamento) : null
  }
}

export function mensagemPagamentoErro(code: PagamentoErrorCode): string {
  const mapa: Record<PagamentoErrorCode, string> = {
    CHECKOUT_INVALIDO: 'Não foi possível localizar este checkout.',
    RESERVA_EXPIRADA: 'Esta reserva não está mais disponível para pagamento.',
    PEDIDO_INDISPONIVEL: 'Este pedido não está disponível para pagamento.',
    PAGAMENTO_INDISPONIVEL: 'Não foi possível iniciar o pagamento agora.',
    ERRO_INESPERADO: 'Não foi possível carregar o pagamento agora. Tente novamente.'
  }
  return mapa[code]
}

function mapearErro(error: RpcErrorLike): PagamentoError {
  const mensagem = (error.message ?? '').toLowerCase()

  if (mensagem.includes('checkout nao encontrado')) {
    return new PagamentoError('CHECKOUT_INVALIDO', error.message ?? 'Checkout inválido')
  }
  if (mensagem.includes('expirada')) {
    return new PagamentoError('RESERVA_EXPIRADA', error.message ?? 'Reserva expirada')
  }
  if (mensagem.includes('nao esta reservado')) {
    return new PagamentoError('PEDIDO_INDISPONIVEL', error.message ?? 'Pedido indisponível')
  }
  return new PagamentoError('ERRO_INESPERADO', error.message ?? 'Erro inesperado')
}

export async function obterCheckoutPedido(token: string): Promise<CheckoutPublico | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_checkout_pedido', { p_token: token })
  if (error) throw mapearErro(error)
  if (data === null) return null
  return mapearCheckout(data as CheckoutRpcRow)
}

export async function criarPagamentoPendente(token: string): Promise<CheckoutPublicoPagamento> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('criar_pagamento_pendente_por_token', {
    p_token: token,
    p_provider: 'MERCADO_PAGO',
    p_transaction_id: null,
    p_charge_id: null,
    p_referencia_externa: null
  })
  if (error) throw mapearErro(error)
  return mapearPagamento(data as CheckoutRpcPagamento)
}
