export type PerfilUsuario = 'ADMINISTRADOR' | 'PORTARIA' | 'SOCIO'

/** Evento acompanhado por um Socio do Evento. */
export interface EventoSocioResumo {
  id: string
  nome: string
}

export interface AdminUsuarioRow {
  id: string
  nome: string
  email: string
  perfil: PerfilUsuario
  ativo: boolean
  /** Ainda nao criou a senha (convite nao aceito). */
  pendente?: boolean
  ultimo_acesso_em: string | null
  criado_em: string
  /** Eventos que o Socio do Evento acompanha (vazio para os outros perfis). */
  eventos_socio?: EventoSocioResumo[]
}

export interface UsuarioListItem {
  id: string
  nome: string
  email: string
  perfil: PerfilUsuario
  ativo: boolean
  pendente: boolean
  ultimoAcesso: string
  criadoEm: string
  ehUltimoAdminAtivo: boolean
  eventosSocio: EventoSocioResumo[]
}

export interface ConviteUsuarioInput {
  nome: string
  email: string
  perfil: PerfilUsuario
  /** Somente para SOCIO: eventos que ele vai acompanhar. */
  eventoIds?: string[]
}

export interface EdicaoUsuarioInput {
  id: string
  nome: string
  perfil: PerfilUsuario
  ativo: boolean
  /** Somente para SOCIO: eventos que ele vai acompanhar. */
  eventoIds?: string[]
}

/** Resultado do convite: link para enviar, ou pessoa ja cadastrada vinculada. */
export interface ResultadoConvite {
  link: string | null
  vinculado: boolean
  pendente: boolean
}
