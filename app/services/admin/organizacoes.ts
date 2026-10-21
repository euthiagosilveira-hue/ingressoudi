import { mapearDetalheCasa, type DetalheCasa } from '~/utils/organizacaoPlataforma'

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
  listaVip: boolean
  taxaServico: number
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
    listaVip: Boolean(o.lista_vip_ativa),
    taxaServico: Number(o.taxa_servico ?? 0),
    criadoEm: String(o.criado_em ?? ''),
    mercadoPagoConectado: Boolean(o.mercado_pago_conectado),
    administradores: String(o.administradores ?? ''),
    eventos: Number(o.eventos ?? 0)
  }))
}

/** Dados, equipe, metricas e eventos de uma casa (somente super admin). */
export async function obterOrganizacaoPlataforma(organizacaoId: string): Promise<DetalheCasa> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_organizacao_plataforma', { p_organizacao_id: organizacaoId })
  if (error || !data) {
    const m = (error?.message ?? '').toLowerCase()
    if (m.includes('permiss')) throw new Error('Apenas o super administrador vê os detalhes das casas.')
    if (m.includes('nao encontrada')) throw new Error('Casa não encontrada.')
    throw new Error('Não foi possível carregar a casa.')
  }
  return mapearDetalheCasa(data as Record<string, unknown>)
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

/** Liga (true) ou desliga (false) a Lista VIP de uma casa (somente super admin). */
export async function definirListaVipOrganizacao(organizacaoId: string, ativa: boolean): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('definir_lista_vip_organizacao', {
    p_organizacao_id: organizacaoId,
    p_ativa: ativa
  })
  if (error) throw new Error('Não foi possível atualizar a Lista VIP.')
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
