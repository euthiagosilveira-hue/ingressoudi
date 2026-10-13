export type PerfilOperador = 'ADMINISTRADOR' | 'PORTARIA'

export interface OrganizacaoResumo {
  id: string
  nome: string
  slug: string
}

export interface OrganizacaoDoOperador extends OrganizacaoResumo {
  perfil: PerfilOperador
}

/**
 * Sessao do operador (RPC public.obter_sessao_operador).
 * `perfil` e `ativo` referem-se a ORGANIZACAO ATIVA.
 */
export interface OperadorProfile {
  id: string
  nome: string
  email: string
  perfil: PerfilOperador
  ativo: boolean
  superAdmin: boolean
  organizacao: OrganizacaoResumo | null
  organizacoes: OrganizacaoDoOperador[]
}

export type AuthErrorCode =
  | 'CREDENCIAIS_INVALIDAS'
  | 'SEM_USUARIO'
  | 'INATIVO'
  | 'SEM_PERMISSAO'
  | 'ERRO_TEMPORARIO'
