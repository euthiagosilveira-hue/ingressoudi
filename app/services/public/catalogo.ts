import type { EventStatus, SalesStatus } from '~/types/evento'
import type { PublicEventDetail, PublicVendaSituacao } from '~/types/publicEvento'

/**
 * Linha retornada pelaa RPC publica (snake_case).
 * `listar_eventos_publicos` e `obter_evento_publico` retornam a mesma TABLE.
 */
interface EventoPublicoRow {
  evento_id: string
  slug: string
  nome: string
  descricao: string | null
  imagem_url: string | null
  inicio_em: string
  local: string | null
  endereco: string | null
  status: string
  vendas_status: string
  lote_id: string | null
  lote_nome: string | null
  preco: number | string | null
  situacao_venda: string | null
}

interface EventoPublicoOrganizacaoRow extends EventoPublicoRow {
  taxa_servico: number | string | null
  taxa_repassada: boolean | null
  organizacao_slug: string | null
  organizacao_nome: string | null
  organizacao_logo_url: string | null
}

export interface OrganizacaoPublicaDados {
  organizacaoId: string
  nome: string
  slug: string
  logoUrl: string | null
}

export class CatalogoIndisponivelError extends Error {
  constructor(message = 'Catálogo indisponível') {
    super(message)
    this.name = 'CatalogoIndisponivelError'
  }
}

/**
 * RPC snake_case -> dominio publico camelCase.
 * `disponiveis` nao existe no retorno real (fica null); a disponibilidade
 * real e responsabilidade futura de `criar_reserva`.
 */
function mapearEventoPublico(row: EventoPublicoRow): PublicEventDetail {
  return {
    eventoId: row.evento_id,
    slug: row.slug,
    nome: row.nome,
    descricao: row.descricao ?? '',
    imagemUrl: row.imagem_url,
    inicioEm: row.inicio_em,
    local: row.local ?? '',
    endereco: row.endereco ?? '',
    status: row.status as EventStatus,
    vendasStatus: row.vendas_status as SalesStatus,
    publicacaoStatus: 'PUBLICADO',
    loteId: row.lote_id,
    loteNome: row.lote_nome,
    preco: row.preco === null ? null : Number(row.preco),
    disponiveis: null,
    situacaoVenda: (row.situacao_venda ?? 'SEM_LOTE') as PublicVendaSituacao
  }
}

export async function listarEventosPublicos(): Promise<PublicEventDetail[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_publicos')
  if (error) throw new CatalogoIndisponivelError(error.message)

  const rows = (data ?? []) as EventoPublicoRow[]
  return rows.map(mapearEventoPublico)
}

export async function obterEventoPublico(slug: string): Promise<PublicEventDetail | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_evento_publico', { p_slug: slug })
  if (error) throw new CatalogoIndisponivelError(error.message)

  const rows = (data ?? []) as EventoPublicoRow[]
  const row = rows[0]
  if (!row) return null

  const evento = mapearEventoPublico(row)
  evento.taxaServico = await obterTaxaEventoPublico(slug)
  return evento
}

/** Dados publicos da casa (nome, slug, logo). null se nao existir/inativa. */
export async function obterOrganizacaoPublica(slug: string): Promise<OrganizacaoPublicaDados | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_organizacao_publica', { p_slug: slug })
  if (error) throw new CatalogoIndisponivelError(error.message)
  if (!data) return null
  const row = data as { organizacao_id: string; nome: string; slug: string; logo_url: string | null }
  return { organizacaoId: row.organizacao_id, nome: row.nome, slug: row.slug, logoUrl: row.logo_url ?? null }
}

/** Catalogo de uma casa: somente eventos publicados e agendados dela. */
export async function listarEventosPublicosOrganizacao(orgSlug: string): Promise<PublicEventDetail[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_publicos_organizacao', { p_org_slug: orgSlug })
  if (error) throw new CatalogoIndisponivelError(error.message)
  return ((data ?? []) as EventoPublicoRow[]).map((row) => ({
    ...mapearEventoPublico(row),
    organizacaoSlug: orgSlug
  }))
}

/** Evento publicado de uma casa (inclui taxa visivel e marca da casa). */
export async function obterEventoPublicoOrganizacao(
  orgSlug: string,
  eventoSlug: string
): Promise<PublicEventDetail | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_evento_publico_organizacao', {
    p_org_slug: orgSlug,
    p_evento_slug: eventoSlug
  })
  if (error) throw new CatalogoIndisponivelError(error.message)
  const row = ((data ?? []) as EventoPublicoOrganizacaoRow[])[0]
  if (!row) return null
  const taxa = Number(row.taxa_servico ?? 0)
  return {
    ...mapearEventoPublico(row),
    taxaServico: Number.isNaN(taxa) ? 0 : taxa,
    organizacaoSlug: row.organizacao_slug,
    organizacaoNome: row.organizacao_nome,
    organizacaoLogoUrl: row.organizacao_logo_url
  }
}

/** Link antigo /eventos/{slug}: casa + slug quando o slug e unico; senao null. */
export async function resolverEventoPublico(
  slug: string
): Promise<{ organizacaoSlug: string; eventoSlug: string } | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('resolver_evento_publico', { p_slug: slug })
  if (error) throw new CatalogoIndisponivelError(error.message)
  if (!data) return null
  const row = data as { organizacao_slug: string; evento_slug: string }
  return { organizacaoSlug: row.organizacao_slug, eventoSlug: row.evento_slug }
}

/** Taxa por ingresso exibida ao comprador. Falha de leitura nao bloqueia a pagina. */
async function obterTaxaEventoPublico(slug: string): Promise<number> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_taxa_evento_publico', { p_slug: slug })
  if (error || !data) return 0
  const taxa = Number((data as { taxa_servico?: number | string | null }).taxa_servico ?? 0)
  return Number.isNaN(taxa) ? 0 : taxa
}
