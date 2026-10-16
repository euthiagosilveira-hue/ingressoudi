import { toast } from 'vue3-toastify'

import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { obterEventoAdmin } from '~/services/admin/eventos'
import { copiarTexto, urlEventoPublico } from '~/utils/linkEvento'

/** Copia o link publico de um evento da casa ativa e avisa com um toast. */
export function useCopiarLinkEvento() {
  const { operador } = useOperatorAuth()
  const config = useRuntimeConfig()

  function linkEvento(eventoSlug: string): string {
    const origem =
      typeof window !== 'undefined' ? window.location.origin : String(config.public.siteUrl || '')
    return urlEventoPublico(origem, operador.value?.organizacao?.slug, eventoSlug)
  }

  /**
   * Sem o slug em maos (ex.: cabecalho dos lotes), busca o evento pelo id
   * antes de copiar.
   */
  async function copiarLinkEvento(eventoSlug: string, eventoId?: string): Promise<void> {
    let slug = eventoSlug
    if (!slug && eventoId) {
      try {
        slug = (await obterEventoAdmin(eventoId)).slug
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Não foi possível obter o link do evento.')
        return
      }
    }
    if (!slug) {
      toast.error('Não foi possível obter o link do evento.')
      return
    }

    const link = linkEvento(slug)
    if (await copiarTexto(link)) {
      toast.success('Link copiado! Agora é só colar onde quiser divulgar.')
    } else {
      toast.error(`Não foi possível copiar. Copie manualmente: ${link}`)
    }
  }

  return { linkEvento, copiarLinkEvento }
}
