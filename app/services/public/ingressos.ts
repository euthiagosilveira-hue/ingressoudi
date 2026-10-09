import type { OrderStatus } from '~/types/pedido'
import type {
  PublicOrderTickets,
  PublicTicket,
  PublicTicketStatus,
  TicketsErrorCode
} from '~/types/publicIngressos'

interface IngressoRpc {
  ingresso_id: string
  codigo: string
  participante_nome: string
  status: string
  qr_token: string | null
  utilizado_em: string | null
}

interface IngressosRpc {
  pedido_id: string
  codigo_pedido: string
  evento_id: string
  evento_slug: string
  evento_nome: string
  evento_inicio_em: string
  evento_local: string
  evento_endereco: string
  pedido_status: string
  disponivel: boolean
  ingressos: IngressoRpc[] | null
}

interface RpcErrorLike {
  message?: string | null
}

export class TicketsError extends Error {
  code: TicketsErrorCode

  constructor(code: TicketsErrorCode, message: string) {
    super(message)
    this.name = 'TicketsError'
    this.code = code
  }
}

function mapearIngresso(row: IngressoRpc): PublicTicket {
  return {
    ingressoId: row.ingresso_id,
    codigo: row.codigo,
    participanteNome: row.participante_nome,
    status: row.status as PublicTicketStatus,
    qrToken: row.qr_token,
    utilizadoEm: row.utilizado_em
  }
}

function mapearTickets(row: IngressosRpc): PublicOrderTickets {
  return {
    pedidoId: row.pedido_id,
    codigoPedido: row.codigo_pedido,
    eventoId: row.evento_id,
    eventoSlug: row.evento_slug,
    eventoNome: row.evento_nome,
    eventoInicioEm: row.evento_inicio_em,
    eventoLocal: row.evento_local,
    eventoEndereco: row.evento_endereco,
    pedidoStatus: row.pedido_status as OrderStatus,
    disponivel: row.disponivel === true,
    ingressos: (row.ingressos ?? []).map(mapearIngresso)
  }
}

/**
 * Recupera os ingressos do pedido via checkout_token (bearer).
 * Retorna null quando o token nao corresponde a nenhum pedido.
 * Acesso somente via RPC publica `obter_ingressos_checkout` (sem SELECT direto).
 */
export async function obterIngressosCheckout(token: string): Promise<PublicOrderTickets | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_ingressos_checkout', { p_token: token })
  if (error) {
    throw new TicketsError('ERRO_INESPERADO', (error as RpcErrorLike).message ?? 'Erro inesperado')
  }
  if (data === null) return null
  return mapearTickets(data as IngressosRpc)
}

/**
 * Recupera os ingressos via token de recuperacao temporario (bearer).
 * Mesmo shape de obterIngressosCheckout (reutiliza a UI existente).
 */
export async function obterIngressosRecuperacao(
  token: string
): Promise<PublicOrderTickets | null> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_ingressos_recuperacao', { p_token: token })
  if (error) {
    throw new TicketsError('ERRO_INESPERADO', (error as RpcErrorLike).message ?? 'Erro inesperado')
  }
  if (data === null) return null
  return mapearTickets(data as IngressosRpc)
}
