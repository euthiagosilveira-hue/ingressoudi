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
