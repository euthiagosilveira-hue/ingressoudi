import type { EventListItem, SalesStatus } from '~/types/evento'
import type { LotActivationType, LotListItem, SetorListItem } from '~/types/lote'
import {
  mapearEventoLotesParaListItem,
  mapearLoteAdminParaListItem,
  mapearSetorAdmin,
  type EventoLotesAdminRow,
  type LoteAdminRow,
  type SetorAdminRow
} from '~/utils/lotes'

interface RpcErrorLike {
  code?: string | null
  message?: string | null
}

export interface LotesAdminData {
  evento: EventListItem
  estoqueAntecipado: number
  lotes: LotListItem[]
  setores: SetorListItem[]
}

interface ListarLotesRpc {
  evento: EventoLotesAdminRow | null
  lotes: LoteAdminRow[] | null
  setores?: SetorAdminRow[] | null
}

export interface CriarLoteAdminInput {
  nome: string
  quantidade: number
  preco: number
  tipoAtivacao: LotActivationType
  ativacaoEm: string | null
  /** Setor do lote; null = primeiro setor do evento. */
  setorId?: string | null
}

function mensagemErroLote(error: RpcErrorLike | null, padrao: string): string {
  const e = error ?? {}
  const mensagem = (e.message ?? '').toLowerCase()

  // Regras de dominio conhecidas (mensagens da RPC) tem prioridade.
  if (mensagem.includes('ja existe um setor')) {
    return 'Já existe um setor com esse nome neste evento.'
  }
  if (mensagem.includes('nome do setor muito longo')) {
    return 'O nome do setor pode ter no máximo 40 caracteres.'
  }
  if (mensagem.includes('informe o nome do setor')) {
    return 'Informe o nome do setor.'
  }
  if (mensagem.includes('setor com lotes')) {
    return 'Este setor tem lotes e não pode ser excluído.'
  }
  if (mensagem.includes('pelo menos um setor')) {
    return 'O evento precisa de pelo menos um setor.'
  }
  if (mensagem.includes('limite de 10 setores')) {
    return 'O evento pode ter no máximo 10 setores.'
  }
  if (mensagem.includes('nao permite alterar setores')) {
    return 'Este evento não permite mais alterar setores.'
  }
  if (mensagem.includes('nao pertence ao evento')) {
    return 'Este setor não pertence ao evento.'
  }
  if (mensagem.includes('vendas encerradas')) {
    return 'Abra as vendas do evento antes de ativar um lote.'
  }
  if (mensagem.includes('nao permite ativacao') || mensagem.includes('nao permite alterar vendas')) {
    return 'Este evento não permite essa ação.'
  }
  if (mensagem.includes('lotes encerrados')) {
    return 'Lotes encerrados não podem ser editados.'
  }
  if (mensagem.includes('sem ingressos disponiveis')) {
    return 'Este lote está encerrado e não tem mais ingressos disponíveis.'
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
  if (mensagem.includes('nao esta ativo')) {
    return 'Este lote não está ativo.'
  }
  if (mensagem.includes('nao permite encerrar')) {
    return 'Este evento não permite essa ação.'
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
    lotes: (payload.lotes ?? []).map(mapearLoteAdminParaListItem),
    setores: (payload.setores ?? []).map(mapearSetorAdmin)
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
    p_ativacao_em: input.ativacaoEm,
    // So enviado quando o evento tem setores (banco ja com a migracao de setores).
    ...(input.setorId ? { p_setor_id: input.setorId } : {})
  })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível criar o lote.'))
  }
}

/** Cria um setor no evento (ex.: Camarote). RPC segura, ADMINISTRADOR. */
export async function criarSetorAdmin(eventoId: string, nome: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('criar_setor_admin', { p_evento_id: eventoId, p_nome: nome })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível criar o setor.'))
  }
}

/** Renomeia um setor. RPC segura, ADMINISTRADOR. */
export async function renomearSetorAdmin(setorId: string, nome: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('renomear_setor_admin', { p_setor_id: setorId, p_nome: nome })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível renomear o setor.'))
  }
}

/** Exclui um setor sem lotes. RPC segura, ADMINISTRADOR. */
export async function excluirSetorAdmin(setorId: string): Promise<void> {
  const client = useSupabaseClient()
  const { error } = await client.rpc('excluir_setor_admin', { p_setor_id: setorId })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível excluir o setor.'))
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

export interface EncerrarLoteResultado {
  loteAtivadoNome: string | null
}

/** Encerra o lote ATIVO agora; opcionalmente ativa o proximo lote INATIVO (RPC, ADMINISTRADOR). */
export async function encerrarLoteAdmin(
  loteId: string,
  ativarProximo: boolean
): Promise<EncerrarLoteResultado> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('encerrar_lote_admin', {
    p_lote_id: loteId,
    p_ativar_proximo: ativarProximo
  })
  if (error) {
    throw new Error(mensagemErroLote(error, 'Não foi possível encerrar o lote.'))
  }
  const payload = (data ?? {}) as { lote_ativado_nome?: string | null }
  return { loteAtivadoNome: payload.lote_ativado_nome ?? null }
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
