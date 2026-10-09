import type {
  CheckoutDraft,
  CheckoutReservation,
  CheckoutReservationTicket,
  ReservaErrorCode
} from '~/types/checkout'
import { normalizarTelefone } from '~/utils/checkout'

interface CriarReservaIngressoRow {
  id: string
  codigo: string
  participante_nome: string
}

interface CriarReservaRpcRow {
  pedido_id: string
  codigo_pedido: string
  checkout_token?: string | null
  evento_id: string
  lote_id: string
  quantidade: number
  valor_unitario: number | string
  valor_total: number | string
  reserva_expira_em: string
  status: string
  ingressos: CriarReservaIngressoRow[]
}

interface RpcErrorLike {
  message?: string | null
  code?: string | null
}

export class ReservaError extends Error {
  code: ReservaErrorCode

  constructor(code: ReservaErrorCode, message: string) {
    super(message)
    this.name = 'ReservaError'
    this.code = code
  }
}

function mapearIngresso(row: CriarReservaIngressoRow): CheckoutReservationTicket {
  return {
    id: row.id,
    codigo: row.codigo,
    participanteNome: row.participante_nome
  }
}

function mapearReserva(row: CriarReservaRpcRow): CheckoutReservation {
  return {
    pedidoId: row.pedido_id,
    codigoPedido: row.codigo_pedido,
    checkoutToken: row.checkout_token ?? null,
    eventoId: row.evento_id,
    loteId: row.lote_id,
    quantidade: Number(row.quantidade),
    valorUnitario: Number(row.valor_unitario),
    valorTotal: Number(row.valor_total),
    reservaExpiraEm: row.reserva_expira_em,
    status: row.status,
    ingressos: (row.ingressos ?? []).map(mapearIngresso)
  }
}

/**
 * Converte o erro tecnico da RPC em erro de dominio.
 * A RPC lanca exceptions com mensagens PT; usamos a mensagem como
 * discriminador (complementando o SQLSTATE, que sozinho nao distingue o caso).
 */
function mapearErro(error: RpcErrorLike): ReservaError {
  const mensagem = (error.message ?? '').toLowerCase()

  if (mensagem.includes('estoque insuficiente') || mensagem.includes('limite do lote')) {
    return new ReservaError('SEM_ESTOQUE', error.message ?? 'Estoque insuficiente')
  }
  if (mensagem.includes('vendas encerradas')) {
    return new ReservaError('VENDAS_ENCERRADAS', error.message ?? 'Vendas encerradas')
  }
  if (mensagem.includes('cancelado')) {
    return new ReservaError('EVENTO_CANCELADO', error.message ?? 'Evento cancelado')
  }
  if (mensagem.includes('lote ativo') || mensagem.includes('nenhum lote')) {
    return new ReservaError('SEM_LOTE', error.message ?? 'Sem lote ativo')
  }
  if (
    mensagem.includes('nao esta agendado') ||
    mensagem.includes('nao esta publicado') ||
    mensagem.includes('ja iniciado') ||
    mensagem.includes('nao encontrado')
  ) {
    return new ReservaError('EVENTO_INDISPONIVEL', error.message ?? 'Evento indisponível')
  }
  if (
    mensagem.includes('obrigatorio') ||
    mensagem.includes('participante') ||
    mensagem.includes('comprador')
  ) {
    return new ReservaError('DADOS_INVALIDOS', error.message ?? 'Dados inválidos')
  }

  return new ReservaError('ERRO_INESPERADO', error.message ?? 'Erro inesperado')
}

/**
 * Cria a reserva real via public.criar_reserva.
 * Envia apenas dados legitimos de entrada; preco/total/lote/expiracao/codigos
 * sao decididos pelo banco.
 */
export async function criarReserva(
  eventoId: string,
  draft: CheckoutDraft
): Promise<CheckoutReservation> {
  const client = useSupabaseClient()

  const { data, error } = await client.rpc('criar_reserva', {
    p_evento_id: eventoId,
    p_comprador_nome: draft.comprador.nome.trim(),
    p_comprador_telefone: normalizarTelefone(draft.comprador.telefone),
    p_comprador_email: draft.comprador.email.trim(),
    p_nomes_participantes: draft.participantes.map((participante) => participante.nome.trim())
  })

  if (error) throw mapearErro(error)

  return mapearReserva(data as CriarReservaRpcRow)
}
