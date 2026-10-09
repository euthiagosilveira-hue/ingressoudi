import type {
  AdminPedidoDetalheRow,
  AdminPedidoPagamentoRaw,
  AdminPedidoRow,
  OrderDetail,
  OrderFiltersState,
  OrderHistoryEvent,
  OrderListItem,
  OrderPriceType,
  OrderSort,
  OrderStatus,
  OrderSummaryData
} from '~/types/pedido'
import type { OrderPayment, PaymentProvider, PaymentStatus } from '~/types/pagamento'
import type { OrderTicket, TicketStatus } from '~/types/ingresso'

/** Formata telefone (somente digitos) no padrao visual atual. */
export function formatarTelefone(valor: string | null): string {
  const digitos = (valor ?? '').replace(/\D/g, '')
  if (digitos.length === 11) return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 7)}-${digitos.slice(7)}`
  if (digitos.length === 10) return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 6)}-${digitos.slice(6)}`
  return valor ?? ''
}

/** Mapeia a linha administrativa real para o view-model da listagem. */
export function mapearPedidoAdminParaListItem(row: AdminPedidoRow): OrderListItem {
  return {
    id: row.id,
    codigo: row.codigo,
    eventoId: row.evento_id,
    eventoNome: row.evento_nome,
    loteId: row.lote_id,
    loteNome: row.lote_nome,
    compradorNome: row.comprador_nome,
    telefone: formatarTelefone(row.comprador_telefone),
    email: row.comprador_email,
    quantidade: Number(row.quantidade),
    tipoPreco: row.tipo_preco as OrderPriceType,
    valorUnitario: Number(row.valor_unitario),
    valorTotal: Number(row.valor_total),
    status: row.status as OrderStatus,
    reservaExpiraEm: row.reserva_expira_em,
    pagoEm: row.pago_em,
    canceladoEm: row.cancelado_em,
    criadoEm: row.criado_em,
    pagamentoProvedor: (row.pagamento_provedor as PaymentProvider | null) ?? null
  }
}

function mapearPagamento(raw: AdminPedidoPagamentoRaw): OrderPayment {
  return {
    id: raw.id,
    status: raw.status as PaymentStatus,
    valor: Number(raw.valor),
    provider: raw.provedor as PaymentProvider,
    transactionId: raw.transacao_id,
    chargeId: raw.cobranca_id,
    externalReference: raw.referencia_externa ?? '',
    expiraEm: raw.expira_em,
    confirmadoEm: raw.confirmado_em,
    canceladoEm: raw.cancelado_em,
    reembolsadoEm: raw.reembolsado_em,
    valorReembolsado: Number(raw.valor_reembolsado ?? 0)
  }
}

function montarHistorico(
  pedido: OrderListItem,
  pagamento: OrderPayment | null
): OrderHistoryEvent[] {
  const eventos: OrderHistoryEvent[] = [
    {
      id: `${pedido.id}_h1`,
      tipo: 'PEDIDO_CRIADO',
      titulo: 'Pedido criado',
      descricao: `Pedido ${pedido.codigo} registrado.`,
      ocorridoEm: pedido.criadoEm
    }
  ]

  if (pedido.status !== 'CANCELADO') {
    eventos.push({
      id: `${pedido.id}_h2`,
      tipo: 'RESERVA_CRIADA',
      titulo: 'Reserva criada',
      descricao: `Reserva de ${pedido.quantidade} ingresso(s).`,
      ocorridoEm: pedido.criadoEm
    })
    eventos.push({
      id: `${pedido.id}_h3`,
      tipo: 'PAGAMENTO_INICIADO',
      titulo: 'Pagamento iniciado',
      descricao: 'Aguardando confirmação do provedor.',
      ocorridoEm: pedido.criadoEm
    })
  }

  if (pedido.status === 'PAGO' && pedido.pagoEm) {
    eventos.push({
      id: `${pedido.id}_h4`,
      tipo: 'PAGAMENTO_APROVADO',
      titulo: 'Pagamento aprovado',
      ocorridoEm: pagamento?.confirmadoEm ?? pedido.pagoEm
    })
    eventos.push({
      id: `${pedido.id}_h5`,
      tipo: 'INGRESSOS_LIBERADOS',
      titulo: 'Ingressos liberados',
      ocorridoEm: pedido.pagoEm
    })
  }

  if (pedido.status === 'EXPIRADO' && pedido.reservaExpiraEm) {
    eventos.push({
      id: `${pedido.id}_h6`,
      tipo: 'PEDIDO_EXPIRADO',
      titulo: 'Pedido expirado',
      descricao: 'A reserva ultrapassou o prazo sem confirmação de pagamento.',
      ocorridoEm: pedido.reservaExpiraEm
    })
  }

  if (pedido.status === 'CANCELADO' && pedido.canceladoEm) {
    eventos.push({
      id: `${pedido.id}_h7`,
      tipo: 'PEDIDO_CANCELADO',
      titulo: 'Pedido cancelado',
      ocorridoEm: pedido.canceladoEm
    })
  }

  return eventos
}

/** Mapeia a linha de detalhe real para o view-model da tela de detalhe. */
export function mapearPedidoAdminParaDetalhe(row: AdminPedidoDetalheRow): OrderDetail {
  const base = mapearPedidoAdminParaListItem(row)
  const pagamento = row.pagamento ? mapearPagamento(row.pagamento) : null
  const ingressos: OrderTicket[] = (row.ingressos ?? []).map((i) => ({
    id: i.id,
    codigo: i.codigo,
    participanteNome: i.participante_nome,
    valorUnitario: Number(i.valor_unitario),
    status: i.status as TicketStatus,
    utilizadoEm: i.utilizado_em
  }))

  return {
    ...base,
    atualizadoEm: row.atualizado_em ?? base.criadoEm,
    eventoInicioEm: row.evento_inicio_em ?? null,
    eventoLocal: row.evento_local ?? null,
    motivoValorAvulso: row.motivo_valor_avulso,
    autorizadoPorUsuarioId: null,
    autorizadoPorNome: row.autorizado_por_nome,
    pagamento,
    ingressos,
    historico: montarHistorico(base, pagamento)
  }
}

export function filtrarPedidos(
  pedidos: OrderListItem[],
  filtros: OrderFiltersState
): OrderListItem[] {
  const busca = filtros.busca.trim().toLowerCase()

  return pedidos.filter((pedido) => {
    if (busca) {
      const combina =
        pedido.codigo.toLowerCase().includes(busca) ||
        pedido.compradorNome.toLowerCase().includes(busca)
      if (!combina) return false
    }

    if (filtros.eventoId !== 'TODOS' && pedido.eventoId !== filtros.eventoId) {
      return false
    }

    if (filtros.status !== 'TODOS' && pedido.status !== filtros.status) {
      return false
    }

    if (filtros.tipoPreco !== 'TODOS' && pedido.tipoPreco !== filtros.tipoPreco) {
      return false
    }

    return true
  })
}

export function ordenarPedidos(
  pedidos: OrderListItem[],
  ordenacao: OrderSort
): OrderListItem[] {
  const copia = [...pedidos]

  copia.sort((a, b) => {
    const diferenca = new Date(a.criadoEm).getTime() - new Date(b.criadoEm).getTime()
    return ordenacao === 'ANTIGOS' ? diferenca : -diferenca
  })

  return copia
}

export function resumoPedidos(pedidos: OrderListItem[]): OrderSummaryData {
  return pedidos.reduce<OrderSummaryData>(
    (acumulado, pedido) => {
      acumulado.total += 1

      if (pedido.status === 'PAGO') {
        acumulado.pagos += 1
        acumulado.valorPago += pedido.valorTotal
      } else if (pedido.status === 'RESERVADO') {
        acumulado.reservados += 1
      } else if (pedido.status === 'EXPIRADO') {
        acumulado.expirados += 1
      } else if (pedido.status === 'CANCELADO') {
        acumulado.cancelados += 1
      }

      return acumulado
    },
    { total: 0, pagos: 0, reservados: 0, expirados: 0, cancelados: 0, valorPago: 0 }
  )
}
