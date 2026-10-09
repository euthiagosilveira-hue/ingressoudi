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
   * Quantidade disponivel.
   * - Mocks de desenvolvimento: preenchido.
   * - RPC publica real: retorna null (nao expoe estoque).
   * A validacao real de estoque sera responsabilidade de `criar_reserva`.
   */
  disponiveis: number | null

  situacaoVenda: PublicVendaSituacao
}
