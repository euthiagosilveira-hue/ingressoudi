import type { EventListItem, EventStatus, SalesStatus } from '~/types/evento'
import type {
  LotActivationType,
  LotFormValue,
  LotListItem,
  LotOrdemRef,
  LotStatus
} from '~/types/lote'
import { montarInicioEm, separarInstanteSaoPaulo } from './eventos.ts'
import { imagemValida } from './imagem.ts'

/** As vendas precisam estar ABERTAS para ativar um lote (regra de dominio). */
export function vendasPermitemAtivacao(vendasStatus: SalesStatus): boolean {
  return vendasStatus === 'ABERTAS'
}

/** O evento permite abrir as vendas (ENCERRADAS e ainda editavel). */
export function eventoPermiteAbrirVendas(status: EventStatus, vendasStatus: SalesStatus): boolean {
  return vendasStatus === 'ENCERRADAS' && status !== 'REALIZADO' && status !== 'CANCELADO'
}

/** Um lote INATIVO fica com ativacao bloqueada quando as vendas estao fechadas. */
export function ativacaoLoteBloqueada(status: LotStatus, vendasStatus: SalesStatus): boolean {
  return status === 'INATIVO' && !vendasPermitemAtivacao(vendasStatus)
}

const ROTULOS: Record<LotActivationType, string> = {
  MANUAL: 'Manual',
  ESGOTAMENTO: 'Após esgotamento',
  DATA_HORA: 'Data e hora'
}

const DESCRICOES: Record<LotActivationType, string> = {
  MANUAL: 'Você ativa o lote quando quiser.',
  ESGOTAMENTO: 'Ativa quando o lote atual esgotar.',
  DATA_HORA: 'Ativa automaticamente na data e hora programadas.'
}

export function rotuloAtivacao(tipo: LotActivationType): string {
  return ROTULOS[tipo]
}

export function descricaoAtivacao(tipo: LotActivationType): string {
  return DESCRICOES[tipo]
}

/**
 * Interpreta data/hora de ativacao como America/Sao_Paulo e retorna o instante
 * inequivoco em ISO 8601 UTC. Reutiliza o helper robusto da criacao de eventos.
 */
export function montarAtivacaoEm(data: string, hora: string): string | null {
  const instante = montarInicioEm(data, hora)
  return instante === '' ? null : instante
}

export function proximaOrdem(lotes: LotListItem[]): number {
  if (lotes.length === 0) return 1
  return Math.max(...lotes.map((lote) => lote.ordem)) + 1
}

export function ordemDuplicada(
  ordens: LotOrdemRef[],
  ordem: number,
  idAtual?: string
): boolean {
  return ordens.some((item) => item.ordem === ordem && item.id !== idAtual)
}

/** Linha real de lote retornada por public.listar_lotes_admin. */
export interface LoteAdminRow {
  lote_id: string
  nome: string
  ordem: number
  quantidade: number
  preco: number | string
  tipo_ativacao: LotActivationType
  ativacao_em: string | null
  ativado_em: string | null
  encerrado_em: string | null
  status: LotStatus
  quantidade_vendida: number
  quantidade_disponivel: number
}

/** Bloco "evento" retornado por public.listar_lotes_admin. */
export interface EventoLotesAdminRow {
  evento_id: string
  nome: string
  status: EventListItem['status']
  vendas_status: EventListItem['vendasStatus']
  publicacao_status: EventListItem['publicacaoStatus']
  inicio_em: string
  local: string
  imagem_url: string | null
  capacidade_total: number
  estoque_antecipado: number
  vendidos: number
  disponiveis: number
}

/** dados reais -> view-model do LotManager (nao reescreve a UI). */
export function mapearLoteAdminParaListItem(row: LoteAdminRow): LotListItem {
  return {
    id: row.lote_id,
    eventoId: '',
    nome: row.nome,
    ordem: row.ordem,
    quantidade: row.quantidade,
    preco: Number(row.preco),
    tipoAtivacao: row.tipo_ativacao,
    ativacaoEm: row.ativacao_em,
    ativadoEm: row.ativado_em,
    encerradoEm: row.encerrado_em,
    status: row.status,
    vendidos: row.quantidade_vendida,
    disponiveis: row.quantidade_disponivel
  }
}

/** Bloco evento real -> EventListItem usado pelo cabecalho. */
export function mapearEventoLotesParaListItem(row: EventoLotesAdminRow): EventListItem {
  return {
    id: row.evento_id,
    nome: row.nome,
    slug: '',
    imagemUrl: imagemValida(row.imagem_url),
    inicioEm: row.inicio_em,
    local: row.local,
    status: row.status,
    vendasStatus: row.vendas_status,
    publicacaoStatus: row.publicacao_status,
    loteAtual: null,
    vendidos: row.vendidos,
    disponiveis: row.disponiveis
  }
}

/** Lote real -> estado inicial do LotForm (edicao), com data/hora em Sao Paulo. */
export function mapearLoteParaFormulario(lote: LotListItem): Partial<LotFormValue> {
  const { data, hora } = separarInstanteSaoPaulo(lote.ativacaoEm ?? '')
  return {
    nome: lote.nome,
    ordem: lote.ordem,
    quantidade: lote.quantidade,
    preco: lote.preco,
    tipoAtivacao: lote.tipoAtivacao,
    dataAtivacao: data,
    horaAtivacao: hora,
    status: lote.status
  }
}
