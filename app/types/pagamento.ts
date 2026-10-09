export type PaymentStatus =
  | 'PENDENTE'
  | 'APROVADO'
  | 'REJEITADO'
  | 'CANCELADO'
  | 'EXPIRADO'
  | 'REEMBOLSADO'

export interface OrderPayment {
  id: string
  status: PaymentStatus
  valor: number
  provider: PaymentProvider
  transactionId: string | null
  chargeId: string | null
  externalReference: string
  expiraEm: string | null
  confirmadoEm: string | null
  canceladoEm: string | null
  reembolsadoEm: string | null
  valorReembolsado: number
}

/**
 * Origem/forma de pagamento. DINHEIRO representa a venda manual registrada
 * pelo administrador (sem gateway externo).
 */
export type PaymentProvider = 'STONE' | 'MERCADO_PAGO' | 'DINHEIRO'

/**
 * Status financeiro normalizado do GZ1.
 * A futura integração com a Stone terá uma camada de mapeamento
 * (status/eventos Stone → status interno GZ1) no backend.
 * O frontend NÃO deve espalhar strings de status da Stone.
 */
export type FinancialPaymentStatus = PaymentStatus

export interface PaymentListItem {
  id: string
  pedidoId: string
  pedidoCodigo: string
  eventoId: string
  eventoNome: string
  compradorNome: string
  provider: PaymentProvider
  valor: number
  status: FinancialPaymentStatus
  transactionId: string
  chargeId: string
  externalReference: string
  criadoEm: string
  expiraEm: string | null
  confirmadoEm: string | null
  canceladoEm: string | null
  reembolsadoEm: string | null
  valorReembolsado: number
}

export type FinancialStatusFilter = 'TODOS' | FinancialPaymentStatus

export type FinancialPeriodFilter = 'TODAS' | 'HOJE' | 'SETE_DIAS' | 'TRINTA_DIAS'

export interface FinancialFiltersState {
  busca: string
  eventoId: string
  status: FinancialStatusFilter
  periodo: FinancialPeriodFilter
}

export type FinancialSort = 'RECENTES' | 'ANTIGOS' | 'MAIOR_VALOR' | 'MENOR_VALOR'

export interface FinancialSummaryData {
  total: number
  aprovados: number
  valorAprovado: number
  pendente: number
  reembolsado: number
  liquido: number
}

/** Linha de movimentacao de public.obter_financeiro_admin. */
export interface AdminFinanceMovimentacaoRow {
  pagamento_id: string
  pedido_id: string
  pedido_codigo: string
  evento_id: string
  evento_nome: string
  comprador_nome: string
  provedor: string
  status: string
  valor: number | string
  valor_reembolsado: number | string | null
  transacao_id: string | null
  cobranca_id: string | null
  referencia_externa: string | null
  expira_em: string | null
  confirmado_em: string | null
  cancelado_em: string | null
  reembolsado_em: string | null
  criado_em: string
}

export interface AdminFinanceResumoRow {
  total: number
  aprovados: number
  valorAprovado: number | string
  pendente: number | string
  reembolsado: number | string
  liquido: number | string
}

export interface AdminFinanceResponse {
  resumo: AdminFinanceResumoRow
  movimentacoes: AdminFinanceMovimentacaoRow[] | null
}
