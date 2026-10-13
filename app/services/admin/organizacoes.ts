export interface OrganizacaoCriada {
  organizacao_id: string
  nome: string
  slug: string
}

function mensagemErro(mensagem: string | undefined): string {
  const m = (mensagem ?? '').toLowerCase()
  if (m.includes('ja existe')) return 'Já existe uma organização com esse endereço.'
  if (m.includes('permiss')) return 'Apenas o super administrador pode criar organizações.'
  if (m.includes('informe')) return 'Informe o nome da organização.'
  return 'Não foi possível criar a organização.'
}

/** Cria uma organizacao (somente super admin). Quem cria vira ADMINISTRADOR dela. */
export async function criarOrganizacao(nome: string, slug: string | null): Promise<OrganizacaoCriada> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('criar_organizacao', {
    p_nome: nome,
    p_slug: slug && slug.trim() ? slug.trim() : null
  })
  if (error) throw new Error(mensagemErro(error.message))
  return data as OrganizacaoCriada
}
