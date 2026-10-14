export interface OrganizacaoPublica {
  slug: string
  nome: string
  logoUrl: string | null
}

/**
 * Casa (organizacao) da pagina publica atual. Usada pelo header/footer para
 * mostrar a marca da casa; null nas paginas gerais da plataforma.
 */
export function useOrganizacaoPublica() {
  const organizacao = useState<OrganizacaoPublica | null>('organizacao-publica', () => null)

  function definir(valor: { slug?: string | null; nome?: string | null; logoUrl?: string | null } | null) {
    if (!valor?.slug || !valor?.nome) {
      organizacao.value = null
      return
    }
    organizacao.value = { slug: valor.slug, nome: valor.nome, logoUrl: valor.logoUrl ?? null }
  }

  function limpar() {
    organizacao.value = null
  }

  return { organizacao, definir, limpar }
}
