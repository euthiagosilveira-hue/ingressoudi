import type { EventListItem, SalesStatus } from '~/types/evento'
import type { LotActivationType, LotListItem } from '~/types/lote'
import {
  mapearEventoLotesParaListItem,
  mapearLoteAdminParaListItem,
  type EventoLotesAdminRow,
  type LoteAdminRow
} from '~/utils/lotes'

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

export interface LotesAdminData {
  evento: EventListItem
  estoqueAntecipado: number
  lotes: LotListItem[]
}

interface ListarLotesRpc {
  evento: EventoLotesAdminRow | null
  lotes: LoteAdminRow[] | null
}

export interface CriarLoteAdminInput {
  nome: string
  quantidade: number
  preco: number
  tipoAtivacao: LotActivationType
  ativacaoEm: string | null
}

function mensagemErroLote(error: RpcErrorLike | null, padrao: string): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()

  // Regras de dominio conhecidas (mensagens da RPC) tem prioridade.
  if (mensagem.includes('vendas encerradas')) {
    return 'Abra as vendas do evento antes de ativar um lote.'
  }
  if (mensagem.includes('nao permite ativacao') || mensagem.includes('nao permite alterar vendas')) {
    return 'Este evento não permite essa ação.'
  }
  if (mensagem.includes('lotes encerrados')) {
    return 'Lotes encerrados não podem ser editados.'
  }
  if (mensagem.includes('encerrado e nao pode ser reaberto')) {
    return 'Este lote está encerrado e não pode ser reaberto.'
  }
  if (mensagem.includes('menor que os ingressos')) {
    return 'A quantidade não pode ser menor que os ingressos já comprometidos.'
  }
  if (mensagem.includes('data e hora de ativacao')) {
    return 'Informe a data e hora de ativação.'
  }
  if (mensagem.includes('preco')) {
    return 'O preço não pode ser negativo.'
  }
  if (mensagem.includes('ja esta ativo')) {
    return 'Este lote já está ativo.'
  }
  if (e.code === '42501' || mensagem.includes('permiss')) {
    return 'Você não tem permissão para gerenciar lotes.'
  }
  if (e.code === '23503' || mensagem.includes('nao encontrado')) {
    return 'Evento ou lote não encontrado.'
  }
  if (e.code === '23514') {
    return 'Verifique os dados informados.'
  }
  return padrao
}

/** Lista evento + lotes reais (RPC segura, ADMINISTRADOR). */
export async function listarLotesAdmin(eventoId: string): Promise<LotesAdminData> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_lotes_admin', { p_evento_id: eventoId })
  if (error || !data) {
    throw new Error(mensagemErroLote(error, 'Não foi possível carregar os lotes.'))
  }
  const payload = data as ListarLotesRpc
  if (!payload.evento) {
    throw new Error('Evento não encontrado.')
  }
  return {
    evento: mapearEventoLotesParaListItem(payload.evento),
    estoqueAntecipado: payload.evento.estoque_antecipado,
    lotes: (payload.lotes ?? []).map(mapearLoteAdminParaListItem)
  }
}

/** Cria lote real (RPC segura, ADMINISTRADOR). Ordem calculada no backend. */
export async function criarLoteAdmin(
  eventoId: string,
  input: CriarLoteAdminInput
): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('criar_lote_admin', {
    p_evento_id: eventoId,
    p_nome: input.nome,
    p_quantidade: input.quantidade,
    p_preco: input.preco,
    p_tipo_ativacao: input.tipoAtivacao,
    p_ativacao_em: input.ativacaoEm
  })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível criar o lote.'))
  }
}

/** Ativa lote real reutilizando a regra de dominio existente (RPC). */
export async function ativarLoteAdmin(loteId: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('ativar_lote_manual', { p_lote_id: loteId })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível ativar o lote.'))
  }
}

export interface AtualizarLoteAdminInput {
  nome: string
  quantidade: number
  preco: number
  tipoAtivacao: LotActivationType
  ativacaoEm: string | null
}

/** Edita lote real (RPC segura, ADMINISTRADOR). Regras por status no backend. */
export async function atualizarLoteAdmin(
  loteId: string,
  input: AtualizarLoteAdminInput
): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('atualizar_lote_admin', {
    p_lote_id: loteId,
    p_nome: input.nome,
    p_quantidade: input.quantidade,
    p_preco: input.preco,
    p_tipo_ativacao: input.tipoAtivacao,
    p_ativacao_em: input.ativacaoEm
  })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível atualizar o lote.'))
  }
}

/** Abre/encerra as vendas do evento (RPC de dominio, ADMINISTRADOR). */
export async function definirVendasEventoAdmin(
  eventoId: string,
  vendasStatus: SalesStatus
): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('definir_vendas_evento_admin', {
    p_evento_id: eventoId,
    p_vendas_status: vendasStatus
  })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível alterar as vendas do evento.'))
  }
}
