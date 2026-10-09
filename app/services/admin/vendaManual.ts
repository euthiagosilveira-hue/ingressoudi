import type {
  AdminEventoVendaManualRow,
  CriarVendaManualInput,
  CriarVendaManualResult,
  EventoVendaManual,
  TipoVendaManual
} from '~/types/vendaManual'
import { mapearEventoVendaManual, mensagemErroVendaManual } from '~/utils/vendaManual'

interface CriarVendaManualRpc {
  pedido_id: string
  codigo_pedido: string
  tipo_preco: string
  quantidade: number
  valor_unitario: number | string
  valor_total: number | string
}

/** Eventos elegiveis para venda manual (AGENDADO/EM_ANDAMENTO) com lote ATIVO. */
export async function listarEventosVendaManualAdmin(): Promise<EventoVendaManual[]> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('listar_eventos_venda_manual_admin')
  if (error) {
    throw new Error('Não foi possível carregar os eventos disponíveis para venda manual.')
  }
  return ((data ?? []) as AdminEventoVendaManualRow[]).map(mapearEventoVendaManual)
}

/** Registra venda manual em dinheiro (RPC transacional, ADMINISTRADOR). */
export async function criarVendaManualAdmin(
  input: CriarVendaManualInput
): Promise<CriarVendaManualResult> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('criar_venda_manual_admin', {
    p_evento_id: input.eventoId,
    p_lote_id: input.loteId,
    p_comprador_nome: input.compradorNome,
    p_comprador_telefone: input.compradorTelefone,
    p_participantes: input.participantes,
    p_comprador_email: input.compradorEmail,
    p_tipo_preco: input.tipoPreco,
    p_valor_unitario: input.valorUnitario
  })

  if (error) {
    throw new Error(mensagemErroVendaManual(error))
  }

  const r = data as CriarVendaManualRpc
  return {
    pedidoId: r.pedido_id,
    codigoPedido: r.codigo_pedido,
    tipoPreco: r.tipo_preco as TipoVendaManual,
    quantidade: Number(r.quantidade),
    valorUnitario: Number(r.valor_unitario),
    valorTotal: Number(r.valor_total)
  }
}
