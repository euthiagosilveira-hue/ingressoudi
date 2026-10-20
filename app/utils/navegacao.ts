export type PerfilNavegacao = 'ADMINISTRADOR' | 'PORTARIA' | null

export type PerfilSidebar = Exclude<PerfilNavegacao, null>

export interface ItemNavegacao {
  to: string
  label: string
  allowedProfiles: PerfilSidebar[]
}

/** Itens exclusivos do ADMINISTRADOR (gestao administrativa). */
export const PERFIS_ADMIN: PerfilSidebar[] = ['ADMINISTRADOR']

/** Itens operacionais liberados para ADMINISTRADOR e PORTARIA. */
export const PERFIS_ADMIN_PORTARIA: PerfilSidebar[] = ['ADMINISTRADOR', 'PORTARIA']

/**
 * Regra unica de visibilidade da navegacao por perfil.
 * Sem perfil resolvido (null) nenhum item e liberado (evita flash indevido).
 */
export function podeVerItemSidebar(
  item: Pick<ItemNavegacao, 'allowedProfiles'>,
  perfil: PerfilNavegacao
): boolean {
  if (!perfil) return false
  return item.allowedProfiles.includes(perfil)
}

/**
 * A gestao da Lista VIP e administrativa: apenas ADMINISTRADOR.
 * PORTARIA usa VIP somente pela /portaria (busca + entrada).
 */
export function podeVerListaVip(perfil: PerfilNavegacao): boolean {
  return perfil === 'ADMINISTRADOR'
}

/**
 * A Lista VIP e liberada por organizacao pela plataforma. O super admin
 * enxerga sempre; as demais organizacoes so quando liberada.
 */
export function listaVipLiberada(
  operador: { superAdmin?: boolean; organizacao?: { listaVip?: boolean } | null } | null | undefined
): boolean {
  if (!operador) return false
  return Boolean(operador.superAdmin) || operador.organizacao?.listaVip === true
}
