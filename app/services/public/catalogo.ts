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
  return row ? mapearEventoPublico(row) : null
}
