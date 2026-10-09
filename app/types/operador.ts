import type { PerfilOperador } from '~/types/operador'

export type PerfilOperador = 'ADMINISTRADOR' | 'PORTARIA'

/** Linha real de public.usuarios (somente os campos usados). */
export interface OperadorProfile {
  id: string
  nome: string
  email: string
  perfil: PerfilOperador
  ativo: boolean
}

export type AuthErrorCode =
  | 'CREDENCIAIS_INVALIDAS'
  | 'SEM_USUARIO'
  | 'INATIVO'
  | 'SEM_PERMISSAO'
  | 'ERRO_TEMPORARIO'
