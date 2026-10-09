import type {
  AdminFinanceMovimentacaoRow,
  AdminFinanceResumoRow,
  FinancialFiltersState,
  FinancialPeriodFilter,
  FinancialSort,
  FinancialSummaryData,
  PaymentListItem
} from '~/types/pagamento'
import type { PaymentProvider, PaymentStatus } from '~/types/pagamento'

function normalizarTexto(valor: string): string {
  return valor
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
}

/** Resumo real (faturamento so de pagamentos APROVADOS). */
export function mapearFinanceiroResumo(row: AdminFinanceResumoRow): FinancialSummaryData {
  return {
    total: Number(row.total),
    aprovados: Number(row.aprovados),
    valorAprovado: Number(row.valorAprovado),
    pendente: Number(row.pendente),
    reembolsado: Number(row.reembolsado),
    liquido: Number(row.liquido)
  }
}

/** Mapeia a movimentacao real para o view-model da listagem. */
export function mapearMovimentacaoParaListItem(
  row: AdminFinanceMovimentacaoRow
): PaymentListItem {
  return {
    id: row.pagamento_id,
    pedidoId: row.pedido_id,
    pedidoCodigo: row.pedido_codigo,
    eventoId: row.evento_id,
    eventoNome: row.evento_nome,
    compradorNome: row.comprador_nome,
    provider: row.provedor as PaymentProvider,
    valor: Number(row.valor),
    status: row.status as PaymentStatus,
    transactionId: row.transacao_id ?? '',
    chargeId: row.cobranca_id ?? '',
    externalReference: row.referencia_externa ?? '',
    criadoEm: row.criado_em,
    expiraEm: row.expira_em,
    confirmadoEm: row.confirmado_em,
    canceladoEm: row.cancelado_em,
    reembolsadoEm: row.reembolsado_em,
    valorReembolsado: Number(row.valor_reembolsado ?? 0)
  }
}

export function referenciaTemporalPagamentos(pagamentos: PaymentListItem[]): Date {
  if (pagamentos.length === 0) return new Date()

  const maxima = pagamentos.reduce(
    (maior, pagamento) => Math.max(maior, new Date(pagamento.criadoEm).getTime()),
    0
  )

  return new Date(maxima)
}

function diferencaEmDias(referencia: Date, alvo: Date): number {
  const base = new Date(
    referencia.getFullYear(),
    referencia.getMonth(),
    referencia.getDate()
  ).getTime()
  const comparado = new Date(alvo.getFullYear(), alvo.getMonth(), alvo.getDate()).getTime()
  return Math.round((base - comparado) / 86_400_000)
}

function dentroDoPeriodo(
  criadoEm: string,
  periodo: FinancialPeriodFilter,
  referencia: Date
): boolean {
  if (periodo === 'TODAS') return true

  const dias = diferencaEmDias(referencia, new Date(criadoEm))

  if (periodo === 'HOJE') return dias === 0
  if (periodo === 'SETE_DIAS') return dias >= 0 && dias <= 7
  return dias >= 0 && dias <= 30
}

export function filtrarPagamentos(
  pagamentos: PaymentListItem[],
  filtros: FinancialFiltersState,
  referencia: Date
): PaymentListItem[] {
  const busca = normalizarTexto(filtros.busca)

  return pagamentos.filter((pagamento) => {
    if (busca) {
      const combina =
        normalizarTexto(pagamento.pedidoCodigo).includes(busca) ||
        normalizarTexto(pagamento.compradorNome).includes(busca) ||
        normalizarTexto(pagamento.transactionId).includes(busca) ||
        normalizarTexto(pagamento.externalReference).includes(busca)
      if (!combina) return false
    }

    if (filtros.eventoId !== 'TODOS' && pagamento.eventoId !== filtros.eventoId) {
      return false
    }
    if (filtros.status !== 'TODOS' && pagamento.status !== filtros.status) {
      return false
    }
    if (!dentroDoPeriodo(pagamento.criadoEm, filtros.periodo, referencia)) {
      return false
    }

    return true
  })
}

export function ordenarPagamentos(
  pagamentos: PaymentListItem[],
  ordenacao: FinancialSort
): PaymentListItem[] {
  const copia = [...pagamentos]

  if (ordenacao === 'MAIOR_VALOR') {
    copia.sort((a, b) => b.valor - a.valor)
    return copia
  }

  if (ordenacao === 'MENOR_VALOR') {
    copia.sort((a, b) => a.valor - b.valor)
    return copia
  }

  copia.sort((a, b) => {
    const diferenca = new Date(a.criadoEm).getTime() - new Date(b.criadoEm).getTime()
    return ordenacao === 'ANTIGOS' ? diferenca : -diferenca
  })

  return copia
}

export function resumoFinanceiro(pagamentos: PaymentListItem[]): FinancialSummaryData {
  const resumo = pagamentos.reduce<FinancialSummaryData>(
    (acumulado, pagamento) => {
      acumulado.total += 1

      if (pagamento.status === 'APROVADO' || pagamento.status === 'REEMBOLSADO') {
        acumulado.valorAprovado += pagamento.valor
      }
      if (pagamento.status === 'APROVADO') {
        acumulado.aprovados += 1
      }
      if (pagamento.status === 'PENDENTE') {
        acumulado.pendente += pagamento.valor
      }

      acumulado.reembolsado += pagamento.valorReembolsado

      return acumulado
    },
    {
      total: 0,
      aprovados: 0,
      valorAprovado: 0,
      pendente: 0,
      reembolsado: 0,
      liquido: 0
    }
  )

  resumo.liquido = resumo.valorAprovado - resumo.reembolsado

  return resumo
}
