export type PerfilUsuario = 'ADMINISTRADOR' | 'PORTARIA'

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
}

export interface ConviteUsuarioInput {
  nome: string
  email: string
  perfil: PerfilUsuario
}

export interface EdicaoUsuarioInput {
  id: string
  nome: string
  perfil: PerfilUsuario
  ativo: boolean
}

/** Resultado do convite: link para enviar, ou pessoa ja cadastrada vinculada. */
export interface ResultadoConvite {
  link: string | null
  vinculado: boolean
  pendente: boolean
}
