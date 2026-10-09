const JANELA_MS = 60_000
const MAX_POR_JANELA = 60

const registros = new Map<string, { inicio: number; total: number }>()

/**
 * Rate limit minimo em memoria (best-effort por instancia serverless).
 * Suficiente para dificultar abuso; nao substitui um limitador distribuido.
 */
export function limitar(event: { node?: { req?: { socket?: { remoteAddress?: string } } }; headers?: unknown }, maximo = MAX_POR_JANELA): boolean {
  const evento = event as {
    node?: { req?: { socket?: { remoteAddress?: string } } }
  }
  const encabecalhos = event.headers as Record<string, string> | undefined
  const ip =
    encabecalhos?.['x-forwarded-for']?.split(',')[0]?.trim() ||
    evento.node?.req?.socket?.remoteAddress ||
    'desconhecido'

  const agora = Date.now()
  const atual = registros.get(ip)

  if (!atual || agora - atual.inicio > JANELA_MS) {
    registros.set(ip, { inicio: agora, total: 1 })
    return true
  }

  atual.total += 1
  return atual.total <= maximo
}
