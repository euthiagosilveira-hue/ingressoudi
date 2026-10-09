import type {
  AdminEventDetail,
  AdminEventListItem,
  EventStatus,
  PublicationStatus,
  SalesStatus
} from '~/types/evento'
import { imagemValida } from '~/utils/imagem'

export interface AdminEventFiltros {
  busca?: string | null
  status?: EventStatus | null
  publicacao?: PublicationStatus | null
  vendas?: SalesStatus | null
}

interface AdminEventRow {
  evento_id: string
  nome: string
  slug: string
  inicio_em: string
  local: string
  status: string
  vendas_status: string
  publicacao_status: string
  capacidade_total: number
  estoque_antecipado: number
  publicado_em: string | null
  imagem_url: string | null
  lote_ativo_id: string | null
  lote_ativo_nome: string | null
  lote_ativo_ordem: number | null
  lote_ativo_preco: number | string | null
  lote_ativo_quantidade: number | null
  lote_ativo_vendidos: number | null
  lote_ativo_disponiveis: number | null
  lotes_count: number
  pedidos_count: number
  ingressos_count: number
}

function mapear(row: AdminEventRow): AdminEventListItem {
  return {
    eventoId: row.evento_id,
    nome: row.nome,
    slug: row.slug,
    inicioEm: row.inicio_em,
    local: row.local,
    status: row.status as EventStatus,
    vendasStatus: row.vendas_status as SalesStatus,
    publicacaoStatus: row.publicacao_status as PublicationStatus,
    capacidadeTotal: row.capacidade_total,
    estoqueAntecipado: row.estoque_antecipado,
    publicadoEm: row.publicado_em,
    imagemUrl: row.imagem_url,
    loteAtivo: row.lote_ativo_id
      ? {
          id: row.lote_ativo_id,
          nome: row.lote_ativo_nome ?? '',
          ordem: row.lote_ativo_ordem ?? 0,
          preco: Number(row.lote_ativo_preco ?? 0),
          quantidade: row.lote_ativo_quantidade ?? 0,
          vendidos: row.lote_ativo_vendidos ?? 0,
          disponiveis: row.lote_ativo_disponiveis ?? 0
        }
      : null,
    lotesCount: row.lotes_count,
    pedidosCount: row.pedidos_count,
    ingressosCount: row.ingressos_count
  }
}

/** Listagem administrativa real de eventos (RPC segura, ADMINISTRADOR). */
export async function listarEventosAdmin(
  filtros: AdminEventFiltros = {}
): Promise<AdminEventListItem[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_admin_filtrado', {
    p_busca: filtros.busca?.trim() ? filtros.busca.trim() : null,
    p_status: filtros.status ?? null,
    p_publicacao: filtros.publicacao ?? null,
    p_vendas: filtros.vendas ?? null
  })
  if (error) {
    throw new Error('Não foi possível carregar os eventos.')
  }
  const rows = (data ?? []) as AdminEventRow[]
  return rows.map(mapear)
}

export interface CriarEventoAdminInput {
  nome: string
  slug: string
  descricao?: string | null
  imagemUrl?: string | null
  inicioEm: string
  local: string
  endereco: string
  capacidadeTotal: number
  estoqueAntecipado: number
  publicacaoStatus: PublicationStatus
  vendasStatus: SalesStatus
}

export interface CriarEventoAdminResult {
  eventoId: string
  slug: string
  nome: string
  status: EventStatus
  publicacaoStatus: PublicationStatus
}

interface CriarEventoRpc {
  evento_id: string
  slug: string
  nome: string
  status: string
  publicacao_status: string
}

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

function mensagemErroEvento(error: RpcErrorLike | null, padrao: string): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()
  if (e.code === '42501' || mensagem.includes('permiss')) {
    return 'Você não tem permissão para gerenciar eventos.'
  }
  if (e.code === '23505' || mensagem.includes('endereco de url')) {
    return 'Já existe um evento com esse endereço de URL.'
  }
  if (e.code === '23503' || mensagem.includes('nao encontrado')) {
    return 'Evento não encontrado.'
  }
  if (e.code === '23514') {
    return 'Verifique os dados informados.'
  }
  return padrao
}

/** Cria um evento real (RPC segura, ADMINISTRADOR). Sem INSERT direto. */
export async function criarEventoAdmin(
  input: CriarEventoAdminInput
): Promise<CriarEventoAdminResult> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('criar_evento_admin', {
    p_nome: input.nome,
    p_slug: input.slug,
    p_descricao: input.descricao ?? null,
    p_imagem_url: imagemValida(input.imagemUrl),
    p_inicio_em: input.inicioEm,
    p_local: input.local,
    p_endereco: input.endereco,
    p_capacidade_total: input.capacidadeTotal,
    p_estoque_antecipado: input.estoqueAntecipado,
    p_publicacao_status: input.publicacaoStatus,
    p_vendas_status: input.vendasStatus
  })

  if (error) {
    throw new Error(mensagemErroEvento(error, 'Não foi possível criar o evento.'))
  }

  const r = data as CriarEventoRpc
  return {
    eventoId: r.evento_id,
    slug: r.slug,
    nome: r.nome,
    status: r.status as EventStatus,
    publicacaoStatus: r.publicacao_status as PublicationStatus
  }
}

interface EventoAdminRow {
  evento_id: string
  nome: string
  slug: string
  descricao: string | null
  imagem_url: string | null
  inicio_em: string
  encerrado_em: string | null
  local: string
  endereco: string
  capacidade_total: number
  estoque_antecipado: number
  status: string
  vendas_status: string
  publicacao_status: string
  publicado_em: string | null
}

function mapearDetalhe(row: EventoAdminRow): AdminEventDetail {
  return {
    eventoId: row.evento_id,
    nome: row.nome,
    slug: row.slug,
    descricao: row.descricao,
    imagemUrl: row.imagem_url,
    inicioEm: row.inicio_em,
    encerradoEm: row.encerrado_em,
    local: row.local,
    endereco: row.endereco,
    capacidadeTotal: row.capacidade_total,
    estoqueAntecipado: row.estoque_antecipado,
    status: row.status as EventStatus,
    vendasStatus: row.vendas_status as SalesStatus,
    publicacaoStatus: row.publicacao_status as PublicationStatus,
    publicadoEm: row.publicado_em
  }
}

/** Obtem um evento real por UUID (RPC segura, ADMINISTRADOR). */
export async function obterEventoAdmin(eventoId: string): Promise<AdminEventDetail> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_evento_admin', { p_evento_id: eventoId })
  if (error || !data) {
    throw new Error(mensagemErroEvento(error, 'Não foi possível carregar o evento.'))
  }
  return mapearDetalhe(data as EventoAdminRow)
}

export interface AtualizarEventoAdminInput {
  nome: string
  slug: string
  descricao?: string | null
  imagemUrl?: string | null
  inicioEm: string
  local: string
  endereco: string
  capacidadeTotal: number
  estoqueAntecipado: number
  publicacaoStatus: PublicationStatus
  vendasStatus: SalesStatus
}

/** Atualiza um evento real (RPC segura, ADMINISTRADOR). status nao e editavel. */
export async function atualizarEventoAdmin(
  eventoId: string,
  input: AtualizarEventoAdminInput
): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('atualizar_evento_admin', {
    p_evento_id: eventoId,
    p_nome: input.nome,
    p_slug: input.slug,
    p_descricao: input.descricao ?? null,
    p_imagem_url: imagemValida(input.imagemUrl),
    p_inicio_em: input.inicioEm,
    p_local: input.local,
    p_endereco: input.endereco,
    p_capacidade_total: input.capacidadeTotal,
    p_estoque_antecipado: input.estoqueAntecipado,
    p_publicacao_status: input.publicacaoStatus,
    p_vendas_status: input.vendasStatus
  })
  if (error) {
    throw new Error(mensagemErroEvento(error, 'Não foi possível atualizar o evento.'))
  }
}
