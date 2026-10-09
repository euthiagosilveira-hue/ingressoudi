import type { PublicEventDetail } from '~/types/publicEvento'
import { listarEventosPublicos, obterEventoPublico } from '~/services/public/catalogo'

/**
 * Catalogo publico com fallback de desenvolvimento.
 *
 * Regra:
 * - PRODUCAO: nunca usa mock; erro tecnico propaga e a pagina mostra estado amigavel.
 * - DESENVOLVIMENTO: se o banco estiver vazio ou a RPC falhar, usa os mocks
 *   (app/data/eventosPublicos.ts) com aviso explicito no console.
 *
 * TODO: remover o fallback mock quando houver eventos reais persistidos e o
 * fluxo validado ponta a ponta.
 */
export function useCatalogoPublico() {
  async function listar(): Promise<{ eventos: PublicEventDetail[]; fallback: boolean }> {
    try {
      const eventos = await listarEventosPublicos()
      if (eventos.length > 0) return { eventos, fallback: false }

      if (import.meta.dev) {
        const mock = await import('~/data/eventosPublicos')
        console.warn('[catalogo] Banco sem eventos publicos; usando mock de desenvolvimento.')
        return { eventos: mock.listarEventosPublicos(), fallback: true }
      }

      return { eventos, fallback: false }
    } catch (erro) {
      if (import.meta.dev) {
        const mock = await import('~/data/eventosPublicos')
        console.warn('[catalogo] Supabase indisponivel; usando mock de desenvolvimento.', erro)
        return { eventos: mock.listarEventosPublicos(), fallback: true }
      }
      throw erro
    }
  }

  async function obter(
    slug: string
  ): Promise<{ evento: PublicEventDetail | null; fallback: boolean }> {
    try {
      const evento = await obterEventoPublico(slug)
      if (evento) return { evento, fallback: false }

      if (import.meta.dev) {
        const mock = await import('~/data/eventosPublicos')
        const doMock = mock.buscarEventoPublico(slug)
        if (doMock) {
          console.warn('[catalogo] Evento ausente no banco; usando mock de desenvolvimento.')
          return { evento: doMock, fallback: true }
        }
      }

      return { evento: null, fallback: false }
    } catch (erro) {
      if (import.meta.dev) {
        const mock = await import('~/data/eventosPublicos')
        console.warn('[catalogo] Supabase indisponivel; usando mock de desenvolvimento.', erro)
        return { evento: mock.buscarEventoPublico(slug), fallback: true }
      }
      throw erro
    }
  }

  return { listar, obter }
}
