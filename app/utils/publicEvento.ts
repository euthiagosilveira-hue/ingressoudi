import type { PublicEventDetail, PublicVendaSituacao } from '~/types/publicEvento'

type DadosSituacao = Pick<
  PublicEventDetail,
  'status' | 'vendasStatus' | 'loteId' | 'disponiveis'
>

/**
 * Utilitarios de apresentacao do dominio publico.
 *
 * `resolverSituacaoVenda` e usado SOMENTE pelos mocks de desenvolvimento.
 * Para eventos reais, a situacao de venda vem pronta do banco
 * (`calcular_situacao_venda` -> coluna `situacao_venda` das RPCs publicas)
 * e NAO deve ser recalculada no frontend.
 */
export function resolverSituacaoVenda(evento: DadosSituacao): PublicVendaSituacao {
  if (evento.status === 'CANCELADO') return 'CANCELADO'
  if (evento.status === 'REALIZADO') return 'ENCERRADO'
  if (evento.status === 'EM_ANDAMENTO') return 'EVENTO_EM_ANDAMENTO'
  if (evento.vendasStatus === 'ENCERRADAS') return 'VENDAS_ENCERRADAS'
  if (!evento.loteId) return 'SEM_LOTE'
  if (evento.disponiveis === 0) return 'ESGOTADO'
  return 'DISPONIVEL'
}

export function descreverSituacaoVenda(situacao: PublicVendaSituacao): string {
  const mapa: Record<PublicVendaSituacao, string> = {
    DISPONIVEL: 'Vendas abertas',
    ESGOTADO: 'Esgotado',
    SEM_LOTE: 'Em breve',
    VENDAS_ENCERRADAS: 'Vendas encerradas',
    EVENTO_EM_ANDAMENTO: 'Em andamento',
    ENCERRADO: 'Encerrado',
    CANCELADO: 'Cancelado'
  }
  return mapa[situacao]
}
