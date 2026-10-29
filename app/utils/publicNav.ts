export interface PublicNavItem {
  to: string
  label: string
  /** Mostrado como botao (ex.: "Meus ingressos"). */
  destaque?: boolean
}

/**
 * Itens da navegacao publica (comprador). Fonte unica usada pelo header,
 * garantindo os mesmos destinos em desktop e mobile.
 *
 * Nunca incluir tokens (qr, checkout ou recovery): o acesso aos ingressos
 * passa sempre pelos pedidos salvos no aparelho ou pela busca (telefone +
 * e-mail, ou codigo do pedido + telefone) em /recuperar-ingressos.
 */
export const PUBLIC_NAV_ITEMS: readonly PublicNavItem[] = [
  { to: '/recuperar-ingressos', label: 'Meus ingressos', destaque: true }
]

/** Na pagina de uma casa, "Eventos" leva ao catalogo daquela casa. */
export function itensNavegacaoPublica(organizacaoSlug?: string | null): PublicNavItem[] {
  const org = String(organizacaoSlug ?? '').trim()
  const itens: PublicNavItem[] = []
  if (org) itens.push({ to: `/${encodeURIComponent(org)}`, label: 'Eventos' })
  return [...itens, ...PUBLIC_NAV_ITEMS]
}
