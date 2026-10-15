/**
 * Politica de reembolso do Ingressoudi (regras puras, testaveis).
 * Direito de desistencia: ate 7 dias apos a compra, desde que o pedido seja
 * feito ate 48h antes do inicio do evento. Devolucao integral (ingressos + taxa).
 * Fora desse prazo, o reembolso fica a criterio do produtor (ex.: evento cancelado).
 */

export const PRAZO_DESISTENCIA_DIAS = 7
export const ANTECEDENCIA_MINIMA_HORAS = 48

export interface SituacaoPrazo {
  dentroDoPrazo: boolean
  motivo: string
}

export function situacaoPrazoDesistencia(
  pagoEm: string | null | undefined,
  eventoInicioEm: string | null | undefined,
  agora: Date = new Date()
): SituacaoPrazo {
  const pago = pagoEm ? new Date(pagoEm) : null
  const inicio = eventoInicioEm ? new Date(eventoInicioEm) : null
  if (!pago || Number.isNaN(pago.getTime())) {
    return { dentroDoPrazo: false, motivo: 'Pedido sem data de pagamento.' }
  }
  const limiteCompra = pago.getTime() + PRAZO_DESISTENCIA_DIAS * 24 * 60 * 60 * 1000
  if (agora.getTime() > limiteCompra) {
    return {
      dentroDoPrazo: false,
      motivo: `Passaram mais de ${PRAZO_DESISTENCIA_DIAS} dias desde a compra.`
    }
  }
  if (inicio && !Number.isNaN(inicio.getTime())) {
    const limiteEvento = inicio.getTime() - ANTECEDENCIA_MINIMA_HORAS * 60 * 60 * 1000
    if (agora.getTime() > limiteEvento) {
      return {
        dentroDoPrazo: false,
        motivo: `Faltam menos de ${ANTECEDENCIA_MINIMA_HORAS} horas para o evento.`
      }
    }
  }
  return { dentroDoPrazo: true, motivo: 'Dentro do prazo de desistência da política.' }
}

/** Algum ingresso do pedido ja entrou na portaria (bloqueia o reembolso). */
export function temIngressoUtilizado(ingressos: Array<{ status: string }>): boolean {
  return ingressos.some((i) => i.status === 'UTILIZADO')
}
