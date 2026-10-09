export type EntryMethod = 'QR_CODE' | 'NOME'

export type EntryState = 'ATIVA' | 'ANULADA'

export interface EntryListItem {
  id: string
  ingressoId: string
  ingressoCodigo: string
  participanteNome: string

  pedidoId: string
  pedidoCodigo: string

  eventoId: string
  eventoNome: string

  usuarioId: string
  usuarioNome: string

  metodo: EntryMethod
  entradaEm: string

  anuladaEm: string | null
  anuladaPorUsuarioId: string | null
  anuladaPorUsuarioNome: string | null
  motivoAnulacao: string | null

  criadoEm: string
}

export type EntryMethodFilter = 'TODOS' | EntryMethod

export type EntryStateFilter = 'TODOS' | EntryState

export type EntryPeriodFilter = 'TODAS' | 'HOJE' | 'SETE_DIAS' | 'TRINTA_DIAS'

export interface EntryFiltersState {
  busca: string
  eventoId: string
  metodo: EntryMethodFilter
  situacao: EntryStateFilter
  periodo: EntryPeriodFilter
}

export type EntrySort = 'RECENTES' | 'ANTIGAS' | 'PARTICIPANTE_AZ'

export interface EntrySummaryData {
  total: number
  ativas: number
  anuladas: number
  qrCode: number
  nome: number
}

/** Linha bruta de public.listar_entradas_admin. */
export interface AdminEntryRow {
  entrada_id: string
  entrada_em: string
  metodo: string
  anulada_em: string | null
  anulada_por_nome: string | null
  motivo_anulacao: string | null
  ingresso_id: string
  ingresso_codigo: string
  participante_nome: string
  ingresso_status: string
  pedido_id: string
  pedido_codigo: string
  evento_id: string
  evento_nome: string
  evento_inicio_em: string | null
  operador_id: string | null
  operador_nome: string | null
  criado_em: string
}
