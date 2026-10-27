import type { PixCharge } from './payment-provider.ts'
import { valorConfere } from './mercado-pago/mercado-pago-payments.ts'

/** Pix registrado no sistema que ainda nao esta APROVADO. */
export interface PixParaConferir {
  pagamentoId: string
  organizacaoId: string
  cobrancaId: string
  valor: number | string
}

export type AvaliacaoCobranca = 'CONFIRMAR' | 'NAO_PAGO' | 'OUTRA_REFERENCIA' | 'VALOR_DIVERGENTE'

/**
 * Decide se a cobranca oficial do Mercado Pago confirma o pagamento interno:
 * so quando esta aprovada, pertence a este pagamento e o valor confere.
 */
export function avaliarCobrancaPix(charge: PixCharge, pix: PixParaConferir): AvaliacaoCobranca {
  if (charge.status !== 'APROVADO') return 'NAO_PAGO'
  if (charge.externalReference && charge.externalReference !== pix.pagamentoId) return 'OUTRA_REFERENCIA'
  if (!valorConfere(charge.amount, pix.valor)) return 'VALOR_DIVERGENTE'
  return 'CONFIRMAR'
}

/** Lista conferida por dia: Pix nao aprovados criados nos ultimos dias. */
export const DIAS_CONFERENCIA_DIARIA = 3
