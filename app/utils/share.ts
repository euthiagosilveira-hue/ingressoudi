export interface ShareData {
  title: string
  text: string
  url: string
}

export type ShareResult = 'compartilhado' | 'copiado' | 'falha'

export function montarShareData(input: { url: string; eventoNome: string }): ShareData {
  return {
    title: 'GZ1 Ingresso',
    text: `Seu ingresso para ${input.eventoNome}`,
    url: input.url
  }
}

/**
 * Compartilha via Web Share API quando disponivel; caso contrario copia o link.
 * Nunca compartilha QR/token diretamente (apenas a URL publica).
 */
export async function compartilharOuCopiar(input: {
  url: string
  eventoNome: string
}): Promise<ShareResult> {
  const data = montarShareData(input)

  const nav = typeof navigator !== 'undefined' ? navigator : undefined

  if (nav && typeof nav.share === 'function') {
    try {
      await nav.share(data)
      return 'compartilhado'
    } catch (e) {
      // Usuario cancelou: nao tratar como erro.
      if ((e as DOMException)?.name === 'AbortError') return 'compartilhado'
    }
  }

  try {
    if (nav?.clipboard?.writeText) {
      await nav.clipboard.writeText(input.url)
      return 'copiado'
    }
  } catch {
    // cai no fallback abaixo
  }

  return 'falha'
}
