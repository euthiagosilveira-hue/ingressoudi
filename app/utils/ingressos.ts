import type {
  AdminTicketDetailRow,
  AdminTicketRow,
  TicketDetail,
  TicketFiltersState,
  TicketHistoryEvent,
  TicketListItem,
  TicketSort,
  TicketStatus,
  TicketSummaryData
} from '~/types/ingresso'
import type { OrderPriceType, OrderStatus } from '~/types/pedido'

/** Mapeia a linha administrativa real para o view-model da listagem. */
export function mapearIngressoAdminParaListItem(row: AdminTicketRow): TicketListItem {
  return {
    id: row.ingresso_id,
    codigo: row.codigo,
    participanteNome: row.participante_nome,
    valorUnitario: Number(row.valor_unitario),
    status: row.status as TicketStatus,
    utilizadoEm: row.utilizado_em,
    pedidoId: row.pedido_id,
    pedidoCodigo: row.pedido_codigo,
    eventoId: row.evento_id,
    eventoNome: row.evento_nome,
    loteId: row.lote_id,
    loteNome: row.lote_nome,
    criadoEm: row.criado_em
  }
}

function montarHistorico(
  base: TicketListItem,
  row: AdminTicketDetailRow
): TicketHistoryEvent[] {
  const eventos: TicketHistoryEvent[] = [
    {
      id: `${base.id}_h1`,
      tipo: 'INGRESSO_RESERVADO',
      titulo: 'Ingresso reservado',
      descricao: `Ingresso ${base.codigo} reservado.`,
      ocorridoEm: base.criadoEm
    }
  ]

  if (base.status === 'VALIDO' || base.status === 'UTILIZADO') {
    eventos.push({
      id: `${base.id}_h3`,
      tipo: 'INGRESSO_LIBERADO',
      titulo: 'Ingresso liberado',
      descricao: 'Ingresso apto para entrada.',
      ocorridoEm: base.criadoEm
    })
  }

  if (base.status === 'UTILIZADO') {
    eventos.push({
      id: `${base.id}_h4`,
      tipo: 'ENTRADA_REGISTRADA',
      titulo: 'Entrada registrada',
      ocorridoEm: row.entrada?.entrada_em ?? base.utilizadoEm ?? base.criadoEm
    })
  }

  if (base.status === 'EXPIRADO') {
    eventos.push({
      id: `${base.id}_h5`,
      tipo: 'INGRESSO_EXPIRADO',
      titulo: 'Ingresso expirado',
      descricao: 'O ingresso expirou junto com a reserva.',
      ocorridoEm: base.criadoEm
    })
  }

  if (base.status === 'CANCELADO') {
    eventos.push({
      id: `${base.id}_h6`,
      tipo: 'INGRESSO_CANCELADO',
      titulo: 'Ingresso cancelado',
      descricao: 'O ingresso foi cancelado e não pode ser utilizado.',
      ocorridoEm: base.criadoEm
    })
  }

  return eventos
}

/** Mapeia a linha de detalhe real para o view-model da tela de detalhe. */
export function mapearIngressoAdminParaDetalhe(row: AdminTicketDetailRow): TicketDetail {
  const base = mapearIngressoAdminParaListItem(row)
  return {
    ...base,
    pedidoStatus: row.pedido_status as OrderStatus,
    tipoPreco: (row.lote_id ? 'LOTE' : 'AVULSO') as OrderPriceType,
    eventoInicioEm: row.evento_inicio_em,
    eventoLocal: row.evento_local,
    valorPedido: Number(row.valor_unitario),
    // Placeholder visual (nunca o qr_token real, que nao e exposto no admin).
    qrMockValue: `DEMO-${base.codigo}`,
    historico: montarHistorico(base, row)
  }
}

export function filtrarIngressos(
  ingressos: TicketListItem[],
  filtros: TicketFiltersState
): TicketListItem[] {
  const busca = filtros.busca.trim().toLowerCase()

  return ingressos.filter((ingresso) => {
    if (busca) {
      const combina =
        ingresso.codigo.toLowerCase().includes(busca) ||
        ingresso.participanteNome.toLowerCase().includes(busca) ||
        ingresso.pedidoCodigo.toLowerCase().includes(busca)
      if (!combina) return false
    }

    if (filtros.eventoId !== 'TODOS' && ingresso.eventoId !== filtros.eventoId) {
      return false
    }

    if (filtros.status !== 'TODOS' && ingresso.status !== filtros.status) {
      return false
    }

    return true
  })
}

export function ordenarIngressos(
  ingressos: TicketListItem[],
  ordenacao: TicketSort
): TicketListItem[] {
  const copia = [...ingressos]

  if (ordenacao === 'PARTICIPANTE_AZ') {
    copia.sort((a, b) => a.participanteNome.localeCompare(b.participanteNome, 'pt-BR'))
    return copia
  }

  copia.sort((a, b) => {
    const diferenca = new Date(a.criadoEm).getTime() - new Date(b.criadoEm).getTime()
    return ordenacao === 'ANTIGOS' ? diferenca : -diferenca
  })

  return copia
}

export function resumoIngressos(ingressos: TicketListItem[]): TicketSummaryData {
  return ingressos.reduce<TicketSummaryData>(
    (acumulado, ingresso) => {
      acumulado.total += 1

      if (ingresso.status === 'VALIDO') acumulado.validos += 1
      else if (ingresso.status === 'UTILIZADO') acumulado.utilizados += 1
      else if (ingresso.status === 'RESERVADO') acumulado.reservados += 1
      else if (ingresso.status === 'CANCELADO') acumulado.cancelados += 1
      else if (ingresso.status === 'EXPIRADO') acumulado.expirados += 1

      return acumulado
    },
    {
      total: 0,
      validos: 0,
      utilizados: 0,
      reservados: 0,
      cancelados: 0,
      expirados: 0
    }
  )
}

export function gerarPadraoQrMock(semente: string, tamanho = 21): boolean[][] {
  let hash = 0
  for (let indice = 0; indice < semente.length; indice += 1) {
    hash = (hash * 31 + semente.charCodeAt(indice)) >>> 0
  }

  const proximo = () => {
    hash ^= hash << 13
    hash >>>= 0
    hash ^= hash >> 17
    hash ^= hash << 5
    hash >>>= 0
    return hash / 0xffffffff
  }

  const grade: boolean[][] = []

  for (let y = 0; y < tamanho; y += 1) {
    const linha: boolean[] = []

    for (let x = 0; x < tamanho; x += 1) {
      const emTopoEsquerda = x < 7 && y < 7
      const emTopoDireita = x >= tamanho - 7 && y < 7
      const emBaseEsquerda = x < 7 && y >= tamanho - 7

      if (emTopoEsquerda || emTopoDireita || emBaseEsquerda) {
        const localX = emTopoEsquerda ? x : emTopoDireita ? x - (tamanho - 7) : x
        const localY = emBaseEsquerda ? y - (tamanho - 7) : y
        const borda = localX === 0 || localX === 6 || localY === 0 || localY === 6
        const centro = localX >= 2 && localX <= 4 && localY >= 2 && localY <= 4
        linha.push(borda || centro)
      } else {
        linha.push(proximo() > 0.5)
      }
    }

    grade.push(linha)
  }

  return grade
}
