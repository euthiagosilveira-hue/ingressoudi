import type { PublicTicketStatus, TicketsErrorCode } from '~/types/publicIngressos'

/** Rotulo amigavel do status do ingresso. */
export function rotuloStatusIngresso(status: PublicTicketStatus): string {
  const mapa: Record<PublicTicketStatus, string> = {
    VALIDO: 'Válido',
    UTILIZADO: 'Utilizado',
    CANCELADO: 'Cancelado',
    EXPIRADO: 'Expirado'
  }
  return mapa[status]
}

/** Somente ingresso VALIDO tem QR utilizavel para nova entrada. */
export function qrUtilizavel(status: PublicTicketStatus): boolean {
  return status === 'VALIDO'
}

/** Normaliza o codigo do pedido (trim + maiusculo). */
export function normalizarCodigoPedido(valor: string): string {
  return (valor ?? '').trim().toUpperCase()
}

/** Normaliza telefone comparando apenas digitos. */
export function normalizarTelefone(valor: string): string {
  return (valor ?? '').replace(/\D/g, '')
}

/** Mensagem amigavel para erros de carregamento dos ingressos. */
export function mensagemTicketsErro(code: TicketsErrorCode): string {
  const mapa: Record<TicketsErrorCode, string> = {
    CHECKOUT_INVALIDO: 'Não foi possível localizar seus ingressos.',
    ERRO_INESPERADO: 'Não foi possível carregar seus ingressos agora. Tente novamente.'
  }
  return mapa[code]
}
