import type { EventStatus, PublicationStatus, SalesStatus } from '~/types/evento'

/**
 * Situacao de venda exibida na pagina publica do evento.
 * Espelha os estados previstos para a futura RPC publica
 * `obter_evento_publico(slug)`.
 */
export type PublicVendaSituacao =
  | 'CANCELADO'
  | 'ENCERRADO'
  | 'EVENTO_EM_ANDAMENTO'
  | 'VENDAS_ENCERRADAS'
  | 'SEM_LOTE'
  | 'ESGOTADO'
  | 'DISPONIVEL'

/** Setor a venda na pagina publica (ex.: Pista, Camarote) com o lote ativo dele. */
export interface PublicSetor {
  setorId: string
  nome: string
  ordem: number
  loteId: string | null
  loteNome: string | null
  preco: number | null
  situacaoVenda: PublicVendaSituacao
}

export interface PublicEventDetail {
  eventoId: string
  slug: string
  nome: string
  descricao: string
  imagemUrl: string | null
  inicioEm: string
  local: string
  endereco: string

  status: EventStatus
  vendasStatus: SalesStatus
  publicacaoStatus: PublicationStatus

  loteId: string | null
  loteNome: string | null
  preco: number | null

  /**
   * Taxa de servico por ingresso paga pelo comprador (0 quando o produtor
   * absorve a taxa). Opcional: mocks de desenvolvimento podem omitir.
   */
  taxaServico?: number

  /** O produtor ligou a meia-entrada neste evento (50% do preco do lote). */
  meiaEntradaAtiva?: boolean

  /** Casa (organizacao) dona do evento. Ausente nos dados antigos/mocks. */
  organizacaoSlug?: string | null
  organizacaoNome?: string | null
  organizacaoLogoUrl?: string | null

  /**
   * Quantidade disponivel.
   * - Mocks de desenvolvimento: preenchido.
   * - RPC publica real: retorna null (nao expoe estoque).
   * A validacao real de estoque sera responsabilidade de `criar_reserva`.
   */
  disponiveis: number | null

  situacaoVenda: PublicVendaSituacao

  /**
   * Setores com lote cadastrado. Com dois ou mais, a pagina mostra um cartao
   * por setor e o checkout compra no setor escolhido.
   */
  setores?: PublicSetor[]

  /** Setor escolhido no checkout (enviado na reserva). */
  setorId?: string | null
  setorNome?: string | null
}