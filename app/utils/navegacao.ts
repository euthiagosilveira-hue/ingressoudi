export type PerfilNavegacao = 'ADMINISTRADOR' | 'PORTARIA' | 'SOCIO' | null

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

/** Itens do Socio do Evento (somente as vendas dos eventos dele). */
export const PERFIS_SOCIO: PerfilSidebar[] = ['SOCIO']

/**
 * Um redirect pos-login so e honrado se o perfil puder abrir aquela area:
 * ADMINISTRADOR qualquer rota interna; PORTARIA so /portaria; SOCIO so /socio.
 */
export function redirectPermitidoPerfil(destino: string, perfil: string | null | undefined): boolean {
  if (perfil === 'ADMINISTRADOR') return true
  if (perfil === 'PORTARIA') return destino === '/portaria' || destino.startsWith('/portaria/') || destino.startsWith('/portaria?')
  if (perfil === 'SOCIO') return destino === '/socio' || destino.startsWith('/socio/') || destino.startsWith('/socio?')
  return false
}

/** Tela inicial de cada perfil depois do login, do convite ou da troca de casa. */
export function destinoInicialPerfil(perfil: string | null | undefined): string {
  if (perfil === 'PORTARIA') return '/portaria'
  if (perfil === 'SOCIO') return '/socio'
  return '/painel'
}

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
