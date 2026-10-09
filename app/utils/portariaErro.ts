import type { TipoErroGate } from '~/types/gate'

/** Timeout das chamadas operacionais da portaria (protege a UI de travar). */
export const REQUEST_TIMEOUT_MS = 8000

/** true quando o navegador informa ausencia de conexao. */
export function estaOffline(nav?: { onLine?: boolean } | null): boolean {
  const alvo = nav === undefined ? (globalThis as { navigator?: { onLine?: boolean } }).navigator : nav
  return Boolean(alvo) && alvo?.onLine === false
}

interface ErroLike {
  name?: string
  code?: string
  message?: string
  status?: number
  statusCode?: number
}

/**
 * Classifica um erro de TRANSPORTE na taxonomia da portaria.
 * Nunca deve ser usada para resultados de negocio (LIBERADO/JA_UTILIZADO/...).
 */
export function classificarErroGate(
  error: unknown,
  contexto?: { online?: boolean }
): TipoErroGate {
  const online =
    contexto && typeof contexto.online === 'boolean' ? contexto.online : !estaOffline()
  if (!online) return 'OFFLINE'

  const e = (error ?? {}) as ErroLike
  const nome = String(e.name ?? '')
  const msg = String(e.message ?? '').toLowerCase()
  const status =
    typeof e.status === 'number'
      ? e.status
      : typeof e.statusCode === 'number'
        ? e.statusCode
        : undefined

  if (nome === 'AbortError' || msg.includes('timeout') || msg.includes('aborted')) {
    return 'TIMEOUT'
  }
  if (
    e.code === '42501' ||
    msg.includes('permiss') ||
    msg.includes('jwt') ||
    (msg.includes('token') && msg.includes('expir')) ||
    msg.includes('session') ||
    msg.includes('sessao') ||
    msg.includes('sessão')
  ) {
    return 'SEM_PERMISSAO'
  }
  if (typeof status === 'number' && status >= 500) return 'SERVIDOR_INDISPONIVEL'
  if (
    nome === 'TypeError' ||
    msg.includes('failed to fetch') ||
    msg.includes('network') ||
    msg.includes('load failed') ||
    msg.includes('fetch failed')
  ) {
    return 'SERVIDOR_INDISPONIVEL'
  }
  return 'DESCONHECIDO'
}

const MENSAGENS: Record<TipoErroGate, string> = {
  OFFLINE: 'Sem conexão com a internet. Verifique a rede e tente novamente.',
  TIMEOUT: 'A consulta demorou mais do que o esperado. Tente novamente.',
  SERVIDOR_INDISPONIVEL: 'O sistema está temporariamente indisponível. Tente novamente.',
  SEM_PERMISSAO: 'Sua sessão não tem permissão para continuar.',
  DESCONHECIDO: 'Não foi possível concluir a operação. Tente novamente.'
}

export function ehErroTecnico(codigo: string | null | undefined): codigo is TipoErroGate {
  return Boolean(codigo) && codigo! in MENSAGENS
}

/** Mensagem curta e operacional (nunca expoe erro cru do provedor). */
export function mensagemErroTecnico(tipo: TipoErroGate): string {
  return MENSAGENS[tipo]
}

/**
 * Envolve um thenable com timeout controlado. Como a versao atual do
 * supabase-js nao expoe AbortSignal no builder de RPC, o timeout protege a UI
 * de ficar pendurada; o backend segue atomico/idempotente caso a resposta se
 * perca.
 */
export function comTimeout<T>(
  thenable: PromiseLike<T>,
  ms: number = REQUEST_TIMEOUT_MS
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | null = null
  const estouro = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new DOMException('Tempo esgotado', 'AbortError')), ms)
  })
  const promessa = Promise.resolve(thenable)
  // Evita "unhandled rejection" se o timeout vencer primeiro.
  promessa.catch(() => {})
  return Promise.race([promessa, estouro]).finally(() => {
    if (timer) clearTimeout(timer)
  })
}
