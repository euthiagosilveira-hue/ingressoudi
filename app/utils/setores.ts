import type { PublicEventDetail, PublicSetor } from '~/types/publicEvento'
import { rotaCheckout } from './rotasPublicas.ts'

/** O evento vende mais de um setor (ex.: Pista e Camarote). */
export function eventoTemSetores(evento: Pick<PublicEventDetail, 'setores'>): boolean {
  return (evento.setores?.length ?? 0) > 1
}

/** Nome exibido do lote no setor: "Camarote · 1º lote". */
export function nomeLoteSetor(setor: Pick<PublicSetor, 'nome' | 'loteNome'>): string {
  return setor.loteNome ? `${setor.nome} · ${setor.loteNome}` : setor.nome
}

/**
 * Evento visto pelo checkout de um setor: lote, preco e situacao passam a ser
 * os do setor escolhido. null quando o setor nao existe no evento.
 */
export function eventoNoSetor(evento: PublicEventDetail, setorId: string | null | undefined): PublicEventDetail | null {
  const setor = evento.setores?.find((item) => item.setorId === setorId)
  if (!setor) return null
  return {
    ...evento,
    loteId: setor.loteId,
    loteNome: nomeLoteSetor(setor),
    preco: setor.preco,
    situacaoVenda: setor.situacaoVenda,
    setorId: setor.setorId,
    setorNome: setor.nome
  }
}

/** Checkout ja no setor escolhido: /{casa}/{evento}/comprar?setor={id}. */
export function rotaCheckoutSetor(
  organizacaoSlug: string | null | undefined,
  eventoSlug: string,
  setorId: string
): string {
  return `${rotaCheckout(organizacaoSlug, eventoSlug)}?setor=${encodeURIComponent(setorId)}`
}
