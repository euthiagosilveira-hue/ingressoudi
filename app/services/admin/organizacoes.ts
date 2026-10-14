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

export interface OrganizacaoPlataforma {
  id: string
  nome: string
  slug: string
  ativo: boolean
  aprovada: boolean
  criadoEm: string
  mercadoPagoConectado: boolean
  administradores: string
  eventos: number
}

/** Todas as casas da plataforma, em analise primeiro (somente super admin). */
export async function listarOrganizacoesPlataforma(): Promise<OrganizacaoPlataforma[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_organizacoes_plataforma')
  if (error) throw new Error('Não foi possível carregar as casas da plataforma.')
  return ((data ?? []) as Array<Record<string, unknown>>).map((o) => ({
    id: String(o.organizacao_id),
    nome: String(o.nome ?? ''),
    slug: String(o.slug ?? ''),
    ativo: Boolean(o.ativo),
    aprovada: Boolean(o.aprovada),
    criadoEm: String(o.criado_em ?? ''),
    mercadoPagoConectado: Boolean(o.mercado_pago_conectado),
    administradores: String(o.administradores ?? ''),
    eventos: Number(o.eventos ?? 0)
  }))
}

/** Aprova (true) ou devolve para analise (false) uma casa (somente super admin). */
export async function definirAprovacaoOrganizacao(organizacaoId: string, aprovada: boolean): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('definir_aprovacao_organizacao', {
    p_organizacao_id: organizacaoId,
    p_aprovada: aprovada
  })
  if (error) throw new Error('Não foi possível atualizar a aprovação.')
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
