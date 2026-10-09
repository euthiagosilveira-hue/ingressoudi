import type {
  CheckoutDraft,
  CheckoutReservation,
  ReservaErrorCode
} from '~/types/checkout'
import type { PublicEventDetail } from '~/types/publicEvento'

export const CHECKOUT_MIN = 1
export const CHECKOUT_MAX = 10
export const RESERVA_MINUTOS = 30

export function limiteQuantidade(disponiveis: number | null): number {
  if (disponiveis === null) return CHECKOUT_MAX
  return Math.max(CHECKOUT_MIN, Math.min(CHECKOUT_MAX, disponiveis))
}

export function nomeValido(valor: string): boolean {
  return valor.trim().length >= 2
}

export function normalizarTelefone(valor: string): string {
  return valor.replace(/\D/g, '')
}

export function telefoneValido(valor: string): boolean {
  const digitos = normalizarTelefone(valor)
  return digitos.length === 10 || digitos.length === 11
}

export function formatarTelefone(valor: string): string {
  const digitos = valor.replace(/\D/g, '').slice(0, 11)
  if (digitos.length === 0) return ''
  if (digitos.length <= 2) return `(${digitos}`
  if (digitos.length <= 6) return `(${digitos.slice(0, 2)}) ${digitos.slice(2)}`
  if (digitos.length <= 10) {
    return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 6)}-${digitos.slice(6)}`
  }
  return `(${digitos.slice(0, 2)}) ${digitos.slice(2, 7)}-${digitos.slice(7)}`
}

export function emailValido(valor: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(valor.trim())
}

export function mensagemErroReserva(codigo: ReservaErrorCode): string {
  const mapa: Record<ReservaErrorCode, string> = {
    SEM_ESTOQUE: 'Não há ingressos suficientes disponíveis para essa quantidade.',
    VENDAS_ENCERRADAS: 'As vendas para este evento foram encerradas.',
    EVENTO_CANCELADO: 'Este evento foi cancelado.',
    EVENTO_INDISPONIVEL: 'Este evento não está disponível para compra.',
    SEM_LOTE: 'Não há lote disponível para venda neste momento.',
    DADOS_INVALIDOS: 'Revise os dados informados e tente novamente.',
    ERRO_INESPERADO: 'Não foi possível criar sua reserva agora. Tente novamente.'
  }
  return mapa[codigo]
}

// ---------------------------------------------------------------------------
// Mock de reserva — usado SOMENTE em desenvolvimento para eventos de
// demonstracao (origem MOCK). Eventos reais nunca passam por aqui.
// TODO: remover quando o fallback de catalogo for eliminado.
// ---------------------------------------------------------------------------

export function gerarCodigoPedidoMock(): string {
  return `GZ${Math.floor(100000 + Math.random() * 900000)}`
}

export function calcularExpiracao(minutos = RESERVA_MINUTOS, base = new Date()): string {
  return new Date(base.getTime() + minutos * 60_000).toISOString()
}

export function criarReservaMock(
  evento: PublicEventDetail,
  draft: CheckoutDraft
): CheckoutReservation {
  const valorUnitario = evento.preco ?? 0
  const codigoPedido = gerarCodigoPedidoMock()

  return {
    pedidoId: `mock-reserva-${Date.now()}`,
    codigoPedido,
    checkoutToken: null,
    eventoId: evento.eventoId,
    loteId: evento.loteId ?? '',
    quantidade: draft.quantidade,
    valorUnitario,
    valorTotal: valorUnitario * draft.quantidade,
    reservaExpiraEm: calcularExpiracao(),
    status: 'RESERVADO',
    ingressos: draft.participantes.map((participante, indice) => ({
      id: `mock-ticket-${indice + 1}`,
      codigo: `${codigoPedido}-${String(indice + 1).padStart(2, '0')}`,
      participanteNome: participante.nome.trim()
    }))
  }
}
