import type { AuthErrorCode, PerfilOperador } from '~/types/operador'

const PERFIS_PERMITIDOS: PerfilOperador[] = ['ADMINISTRADOR', 'PORTARIA']

/**
 * Extrai o UID de um usuario retornado por useSupabaseUser().
 * Na @nuxtjs/supabase v2 esse valor sao as JWT claims (campo `sub`), nao o
 * objeto User (campo `id`). Aceitamos os dois formatos.
 */
export function uidDoUsuario(userValue: unknown): string | null {
  if (!userValue || typeof userValue !== 'object') return null
  const usuario = userValue as { id?: unknown; sub?: unknown }
  if (typeof usuario.id === 'string' && usuario.id.length > 0) return usuario.id
  if (typeof usuario.sub === 'string' && usuario.sub.length > 0) return usuario.sub
  return null
}

/**
 * Retorna o primeiro uid disponivel (nao vazio).
 * Usado para nao depender do timing de useSupabaseUser apos o signIn.
 */
export function resolverUid(...candidatos: Array<string | null | undefined>): string | null {
  for (const candidato of candidatos) {
    if (typeof candidato === 'string' && candidato.length > 0) return candidato
  }
  return null
}

/** Codigo de erro do perfil; null quando autorizado. */
export function codigoErroPerfil(
  perfil: { ativo: boolean; perfil: string } | null
): AuthErrorCode | null {
  if (!perfil) return 'SEM_USUARIO'
  if (!perfil.ativo) return 'INATIVO'
  if (!perfilPermitido(perfil.perfil)) return 'SEM_PERMISSAO'
  return null
}

export function perfilPermitido(perfil: string | null | undefined): boolean {
  return perfil === 'ADMINISTRADOR' || perfil === 'PORTARIA'
}

export type DecisaoAcesso = 'PERMITIR' | 'IR_LOGIN' | 'NEGAR'

/**
 * Decisao pura de acesso a area da portaria (usada pelo middleware).
 * A seguranca real continua no backend/RPC; isto e apenas roteamento/UX.
 */
export function decidirAcessoOperador(input: {
  temSessao: boolean
  perfil: string | null
  ativo: boolean | null
}): DecisaoAcesso {
  if (!input.temSessao) return 'IR_LOGIN'
  if (!perfilPermitido(input.perfil)) return 'NEGAR'
  if (input.ativo !== true) return 'NEGAR'
  return 'PERMITIR'
}

export function mensagemLoginErro(code: AuthErrorCode): string {
  const mapa: Record<AuthErrorCode, string> = {
    CREDENCIAIS_INVALIDAS: 'E-mail ou senha inválidos.',
    SEM_USUARIO: 'Esta conta não está habilitada para a portaria.',
    INATIVO: 'Este usuário está inativo.',
    SEM_PERMISSAO: 'Você não tem permissão para acessar a portaria.',
    ERRO_TEMPORARIO: 'Não foi possível entrar agora. Tente novamente.'
  }
  return mapa[code]
}

/**
 * Sanitiza um destino de redirect. Aceita apenas caminhos internos que comecam
 * com "/" (bloqueia http(s)://, //host, /\, javascript:, data:, etc.).
 */
export function sanitizarRedirect(valor: string | null | undefined): string | null {
  if (typeof valor !== 'string') return null
  const v = valor.trim()
  if (!v.startsWith('/')) return null
  if (v.startsWith('//') || v.startsWith('/\\')) return null
  if (/[\r\n\t]/.test(v)) return null
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(v)) return null
  return v
}
