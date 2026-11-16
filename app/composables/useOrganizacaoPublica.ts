import { computed, watch } from 'vue'

export interface OrganizacaoPublica {
  slug: string
  nome: string
  logoUrl: string | null
  corPrimaria: string | null
}

interface OrganizacaoEntrada {
  slug?: string | null
  nome?: string | null
  logoUrl?: string | null
  /** undefined = desconhecida (busca a marca da casa no banco). */
  corPrimaria?: string | null
}

/**
 * Casa (organizacao) da pagina publica atual. Usada pelo layout/header/footer
 * para mostrar a marca da casa; null nas paginas gerais da plataforma.
 */
export function useOrganizacaoPublica() {
  const organizacao = useState<OrganizacaoPublica | null>('organizacao-publica', () => null)
  // Capturado no setup: pode ser usado depois em callbacks assincronos.
  const client = useSupabaseClient()

  async function completarMarca(slug: string) {
    try {
      const { data } = await client.rpc('obter_organizacao_publica', { p_slug: slug })
      const row = data as { slug?: string; logo_url?: string | null; cor_primaria?: string | null } | null
      if (row && organizacao.value?.slug === slug) {
        organizacao.value = {
          ...organizacao.value,
          logoUrl: row.logo_url ?? null,
          corPrimaria: row.cor_primaria ?? null
        }
      }
    } catch {
      // Marca e apenas visual: falha nao bloqueia a pagina.
    }
  }

  function definir(valor: OrganizacaoEntrada | null) {
    if (!valor?.slug || !valor?.nome) {
      organizacao.value = null
      return
    }
    const atual = organizacao.value?.slug === valor.slug ? organizacao.value : null
    organizacao.value = {
      slug: valor.slug,
      nome: valor.nome,
      logoUrl: valor.logoUrl ?? atual?.logoUrl ?? null,
      corPrimaria: valor.corPrimaria !== undefined ? valor.corPrimaria : (atual?.corPrimaria ?? null)
    }
    if (valor.corPrimaria === undefined && !atual) void completarMarca(valor.slug)
  }

  function limpar() {
    organizacao.value = null
  }

  return { organizacao, definir, limpar }
}

export interface OrganizadorPublico {
  slug: string
  nome: string
  documento: string | null
  tipoDocumento: 'CPF' | 'CNPJ' | null
}

/**
 * Quem organiza os eventos da casa da pagina publica atual (nome e documento
 * para exibicao: CNPJ completo, CPF mascarado). Busca uma vez por casa.
 */
export function useOrganizadorPublico() {
  const { organizacao } = useOrganizacaoPublica()
  const organizador = useState<OrganizadorPublico | null>('organizador-publico', () => null)
  const client = useSupabaseClient()

  async function carregar(slug: string) {
    if (organizador.value?.slug === slug) return
    try {
      const { data } = await client.rpc('obter_organizacao_publica', { p_slug: slug })
      const row = data as {
        organizador_nome?: string | null
        organizador_documento?: string | null
        organizador_tipo_documento?: string | null
      } | null
      if (organizacao.value?.slug !== slug) return
      const tipo = row?.organizador_tipo_documento
      organizador.value = row?.organizador_nome
        ? {
            slug,
            nome: row.organizador_nome,
            documento: row.organizador_documento ?? null,
            tipoDocumento: tipo === 'CPF' || tipo === 'CNPJ' ? tipo : null
          }
        : { slug, nome: '', documento: null, tipoDocumento: null }
    } catch {
      // Informativo: falha nao bloqueia a pagina.
    }
  }

  watch(
    () => organizacao.value?.slug,
    (slug) => {
      if (slug && import.meta.client) void carregar(slug)
    },
    { immediate: true }
  )

  const visivel = computed(() =>
    organizador.value && organizador.value.slug === organizacao.value?.slug && organizador.value.nome
      ? organizador.value
      : null
  )

  return { organizador: visivel }
}
