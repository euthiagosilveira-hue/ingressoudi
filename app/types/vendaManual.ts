import type { EventStatus } from '~/types/evento'

export type EventoStatusVendaManual = Extract<EventStatus, 'AGENDADO' | 'EM_ANDAMENTO'>

/** Modo da venda manual. */
export type TipoVendaManual = 'LOTE' | 'AVULSO'

export interface VendaManualLoteAtivo {
  id: string
  nome: string
  preco: number
  disponiveis: number
}

export interface EventoVendaManual {
  id: string
  nome: string
  inicioEm: string
  local: string
  status: EventoStatusVendaManual
  /** Disponibilidade global do evento (considera ingressos com e sem lote). */
  disponiveisEvento: number
  /** Todos os lotes ATIVOS do evento (hoje no maximo um; futuro: varios). */
  lotesAtivos: VendaManualLoteAtivo[]
  /** Conveniencia: primeiro lote ativo, se houver. */
  loteAtivo: VendaManualLoteAtivo | null
}

/** Linha bruta de public.listar_eventos_venda_manual_admin. */
export interface AdminEventoVendaManualRow {
  evento_id: string
  nome: string
  inicio_em: string
  local: string
  status: string
  estoque_antecipado: number
  disponiveis_evento: number
  lotes_ativos: Array<{
    id: string
    nome: string
    preco: number | string
    disponiveis: number
  }> | null
}

export interface VendaManualForm {
  eventoId: string
  tipo: TipoVendaManual
  loteId: string
  compradorNome: string
  compradorTelefone: string
  compradorEmail: string
  quantidade: number
  /** Somente no modo AVULSO. String por causa do input; convertida no payload. */
  valorUnitario: string
  participantes: string[]
}

export interface CriarVendaManualInput {
  eventoId: string
  loteId: string | null
  compradorNome: string
  compradorTelefone: string | null
  compradorEmail: string | null
  tipoPreco: TipoVendaManual
  valorUnitario: number | null
  participantes: string[]
}

export interface CriarVendaManualResult {
  pedidoId: string
  codigoPedido: string
  tipoPreco: TipoVendaManual
  quantidade: number
  valorUnitario: number
  valorTotal: number
}
