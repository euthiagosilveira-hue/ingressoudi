export interface MarcaOrganizacao {
  organizacaoId: string
  nome: string
  slug: string
  logoUrl: string | null
  corPrimaria: string | null
}

interface MarcaRow {
  organizacao_id: string
  nome: string
  slug: string
  logo_url: string | null
  cor_primaria: string | null
}

function mapear(row: MarcaRow): MarcaOrganizacao {
  return {
    organizacaoId: row.organizacao_id,
    nome: row.nome,
    slug: row.slug,
    logoUrl: row.logo_url ?? null,
    corPrimaria: row.cor_primaria ?? null
  }
}

function mensagem(erro: { message?: string } | null, padrao: string): string {
  const m = (erro?.message ?? '').toLowerCase()
  if (m.includes('permiss')) return 'Apenas administradores podem alterar a página pública.'
  if (m.includes('logo invalido')) return 'Logo inválido. Envie a imagem pelo botão.'
  if (m.includes('cor invalida')) return 'Cor inválida.'
  return padrao
}

export async function obterMarcaOrganizacao(): Promise<MarcaOrganizacao> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_marca_organizacao')
  if (error || !data) throw new Error(mensagem(error, 'Não foi possível carregar a página pública.'))
  return mapear(data as MarcaRow)
}

export async function atualizarMarcaOrganizacao(
  logoUrl: string | null,
  corPrimaria: string | null
): Promise<MarcaOrganizacao> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('atualizar_marca_organizacao', {
    p_logo_url: logoUrl,
    p_cor_primaria: corPrimaria
  })
  if (error || !data) throw new Error(mensagem(error, 'Não foi possível salvar.'))
  return mapear(data as MarcaRow)
}
