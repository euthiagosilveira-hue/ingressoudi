import { MercadoPagoHttpError } from './mercado-pago-client.ts'

/**
 * Reembolso TOTAL de um pagamento (API de Payments), feito com o access_token da
 * conta conectada da organizacao. No marketplace o valor devolvido sai
 * proporcionalmente da conta do vendedor e da comissao da plataforma.
 * Modulo sem auto-imports do Nuxt (testavel com node --test).
 */

const BASE_URL = 'https://api.mercadopago.com'

export interface MpRefund {
  id: number | string
  status?: string | null
  amount?: number | null
}

export async function reembolsarPagamentoMp(
  accessToken: string,
  paymentId: string,
  idempotencyKey: string,
  fetchFn: typeof fetch = fetch
): Promise<MpRefund> {
  const response = await fetchFn(`${BASE_URL}/v1/payments/${encodeURIComponent(paymentId)}/refunds`, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${accessToken}`,
      'X-Idempotency-Key': idempotencyKey,
      // Falhas temporarias (ex.: comunicacao com o Bacen no Pix) voltam como
      // "in_process" em vez de erro 400.
      'X-Render-In-Process-Refunds': 'true'
    },
    // corpo vazio = reembolso total
    body: '{}'
  })
  if (!response.ok) {
    const texto = await response.text().catch(() => '')
    throw new MercadoPagoHttpError(response.status, texto.slice(0, 2000), response.headers.get('x-request-id'))
  }
  return (await response.json()) as MpRefund
}

/** Reembolso aceito pelo Mercado Pago (concluido ou em processamento). */
export function reembolsoAceito(refund: MpRefund | null | undefined): boolean {
  const s = String(refund?.status ?? 'approved').toLowerCase()
  return s === 'approved' || s === 'in_process' || s === 'pending'
}

/** O Mercado Pago informa que o pagamento ja estava reembolsado (ex.: tentativa repetida). */
export function erroJaReembolsado(erro: unknown): boolean {
  if (!(erro instanceof MercadoPagoHttpError)) return false
  const corpo = erro.message.toLowerCase()
  return corpo.includes('already refunded') || corpo.includes('payment already refunded') || corpo.includes('ya fue reembolsado')
}

/** Mensagem amigavel para o produtor a partir do erro do Mercado Pago. */
export function mensagemErroReembolsoMp(erro: unknown): string {
  if (erro instanceof MercadoPagoHttpError) {
    const corpo = erro.message.toLowerCase()
    if (erro.status === 401 || erro.status === 403) {
      return 'A conexão com o Mercado Pago expirou. Reconecte a conta em Configurações → Mercado Pago e tente de novo.'
    }
    if (erro.status === 404) {
      return 'Pagamento não encontrado na conta Mercado Pago conectada.'
    }
    if (corpo.includes('insufficient') || corpo.includes('saldo') || corpo.includes('balance')) {
      return 'Saldo insuficiente na conta Mercado Pago da casa para devolver o valor. Adicione saldo e tente de novo.'
    }
    if (corpo.includes('refunded') || corpo.includes('already')) {
      return 'Este pagamento já foi reembolsado no Mercado Pago.'
    }
    if (corpo.includes('expired') || corpo.includes('days') || corpo.includes('prazo')) {
      return 'O prazo do Mercado Pago para reembolsar este pagamento terminou. A devolução precisa ser feita por fora.'
    }
  }
  return 'Não foi possível concluir o reembolso no Mercado Pago agora. Tente novamente em alguns minutos.'
}
