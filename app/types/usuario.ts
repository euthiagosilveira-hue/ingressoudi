export type PerfilUsuario = 'ADMINISTRADOR' | 'PORTARIA'

export interface AdminUsuarioRow {
  id: string
  nome: string
  email: string
  perfil: PerfilUsuario
  ativo: boolean
  ultimo_acesso_em: string | null
  criado_em: string
}

export interface UsuarioListItem {
  id: string
  nome: string
  email: string
  perfil: PerfilUsuario
  ativo: boolean
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
