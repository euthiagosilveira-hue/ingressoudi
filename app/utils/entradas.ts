import type {
  AdminEntryRow,
  EntryFiltersState,
  EntryListItem,
  EntryMethod,
  EntryPeriodFilter,
  EntrySort,
  EntryState,
  EntrySummaryData
} from '~/types/entrada'

function normalizarTexto(valor: string): string {
  return valor
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
}

/** Mapeia a linha real de public.entradas para o view-model da listagem. */
export function mapearEntradaAdminParaListItem(row: AdminEntryRow): EntryListItem {
  return {
    id: row.entrada_id,
    ingressoId: row.ingresso_id,
    ingressoCodigo: row.ingresso_codigo,
    participanteNome: row.participante_nome,
    pedidoId: row.pedido_id,
    pedidoCodigo: row.pedido_codigo,
    eventoId: row.evento_id,
    eventoNome: row.evento_nome,
    usuarioId: row.operador_id ?? '',
    usuarioNome: row.operador_nome ?? '—',
    metodo: row.metodo as EntryMethod,
    entradaEm: row.entrada_em,
    anuladaEm: row.anulada_em,
    anuladaPorUsuarioId: null,
    anuladaPorUsuarioNome: row.anulada_por_nome,
    motivoAnulacao: row.motivo_anulacao,
    criadoEm: row.criado_em
  }
}

/**
 * `EntryState` é derivado para a UI (a tabela real não possui coluna status):
 * `anulada_em === null` → ATIVA, caso contrário → ANULADA.
 */
export function estadoEntrada(entrada: EntryListItem): EntryState {
  return entrada.anuladaEm ? 'ANULADA' : 'ATIVA'
}

export function referenciaTemporal(entradas: EntryListItem[]): Date {
  if (entradas.length === 0) return new Date()

  const maxima = entradas.reduce(
    (maior, entrada) => Math.max(maior, new Date(entrada.entradaEm).getTime()),
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
  entradaEm: string,
  periodo: EntryPeriodFilter,
  referencia: Date
): boolean {
  if (periodo === 'TODAS') return true

  const dias = diferencaEmDias(referencia, new Date(entradaEm))

  if (periodo === 'HOJE') return dias === 0
  if (periodo === 'SETE_DIAS') return dias >= 0 && dias <= 7
  return dias >= 0 && dias <= 30
}

export function filtrarEntradas(
  entradas: EntryListItem[],
  filtros: EntryFiltersState,
  referencia: Date
): EntryListItem[] {
  const busca = normalizarTexto(filtros.busca)

  return entradas.filter((entrada) => {
    if (busca) {
      const combina =
        normalizarTexto(entrada.participanteNome).includes(busca) ||
        normalizarTexto(entrada.ingressoCodigo).includes(busca) ||
        normalizarTexto(entrada.pedidoCodigo).includes(busca)
      if (!combina) return false
    }

    if (filtros.eventoId !== 'TODOS' && entrada.eventoId !== filtros.eventoId) {
      return false
    }
    if (filtros.metodo !== 'TODOS' && entrada.metodo !== filtros.metodo) {
      return false
    }
    if (filtros.situacao !== 'TODOS' && estadoEntrada(entrada) !== filtros.situacao) {
      return false
    }
    if (!dentroDoPeriodo(entrada.entradaEm, filtros.periodo, referencia)) {
      return false
    }

    return true
  })
}

export function ordenarEntradas(
  entradas: EntryListItem[],
  ordenacao: EntrySort
): EntryListItem[] {
  const copia = [...entradas]

  if (ordenacao === 'PARTICIPANTE_AZ') {
    copia.sort((a, b) => a.participanteNome.localeCompare(b.participanteNome, 'pt-BR'))
    return copia
  }

  copia.sort((a, b) => {
    const diferenca = new Date(a.entradaEm).getTime() - new Date(b.entradaEm).getTime()
    return ordenacao === 'ANTIGAS' ? diferenca : -diferenca
  })

  return copia
}

export function resumoEntradas(entradas: EntryListItem[]): EntrySummaryData {
  return entradas.reduce<EntrySummaryData>(
    (acumulado, entrada) => {
      acumulado.total += 1

      if (estadoEntrada(entrada) === 'ANULADA') acumulado.anuladas += 1
      else acumulado.ativas += 1

      if (entrada.metodo === 'QR_CODE') acumulado.qrCode += 1
      else acumulado.nome += 1

      return acumulado
    },
    { total: 0, ativas: 0, anuladas: 0, qrCode: 0, nome: 0 }
  )
}
