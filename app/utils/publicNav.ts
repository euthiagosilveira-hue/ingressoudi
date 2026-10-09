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
  { to: '/eventos-publicos', label: 'Eventos' },
  { to: '/recuperar-ingressos', label: 'Meus ingressos' }
]
