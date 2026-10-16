import { rotaEvento, urlPublicaAbsoluta } from './rotasPublicas.ts'

/** Link completo da pagina publica do evento (ex.: https://www.ingressoudi.com.br/casa/evento). */
export function urlEventoPublico(
  origem: string | null | undefined,
  organizacaoSlug: string | null | undefined,
  eventoSlug: string
): string {
  return urlPublicaAbsoluta(origem, rotaEvento(organizacaoSlug, eventoSlug))
}

interface ClipboardLike {
  writeText?: (texto: string) => Promise<void>
}

interface DocumentLike {
  createElement: (tag: 'textarea') => HTMLTextAreaElement
  body: { appendChild: (el: HTMLTextAreaElement) => unknown; removeChild: (el: HTMLTextAreaElement) => unknown }
  execCommand?: (comando: string) => boolean
}

/**
 * Copia o texto para a area de transferencia. Usa a Clipboard API e, se ela
 * falhar (navegador antigo ou pagina sem HTTPS), o metodo antigo com textarea.
 */
export async function copiarTexto(
  texto: string,
  clipboard: ClipboardLike | undefined = typeof navigator !== 'undefined' ? navigator.clipboard : undefined,
  doc: DocumentLike | undefined = typeof document !== 'undefined' ? document : undefined
): Promise<boolean> {
  try {
    if (clipboard?.writeText) {
      await clipboard.writeText(texto)
      return true
    }
  } catch {
    // cai no fallback abaixo
  }

  if (!doc?.execCommand) return false
  const campo = doc.createElement('textarea')
  try {
    campo.value = texto
    campo.setAttribute('readonly', '')
    campo.style.position = 'fixed'
    campo.style.opacity = '0'
    doc.body.appendChild(campo)
    campo.select()
    return doc.execCommand('copy') === true
  } catch {
    return false
  } finally {
    try {
      doc.body.removeChild(campo)
    } catch {
      // ja removido
    }
  }
}
