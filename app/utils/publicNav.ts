export interface PublicNavItem {
  to: string
  label: string
}

/**
 * Itens da navegacao publica (comprador). Fonte unica usada pelo header,
 * garantindo os mesmos destinos em desktop e mobile.
 *
 * Nunca incluir tokens (qr, checkout ou recovery): o acesso aos ingressos
 * passa sempre pela validacao de pedido + telefone em /recuperar-ingressos.
 */
export const PUBLIC_NAV_ITEMS: readonly PublicNavItem[] = [
  { to: '/recuperar-ingressos', label: 'Meus ingressos' }
]

/** Na pagina de uma casa, "Eventos" leva ao catalogo daquela casa. */
export function itensNavegacaoPublica(organizacaoSlug?: string | null): PublicNavItem[] {
  const org = String(organizacaoSlug ?? '').trim()
  const itens: PublicNavItem[] = []
  if (org) itens.push({ to: `/${encodeURIComponent(org)}`, label: 'Eventos' })
  return [...itens, ...PUBLIC_NAV_ITEMS]
}
