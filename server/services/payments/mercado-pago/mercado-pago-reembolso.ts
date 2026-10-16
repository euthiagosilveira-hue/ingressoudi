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

/**
 * Detalhe curto do erro devolvido pelo Mercado Pago (message, error e causas),
 * para o log e para o produtor saber o motivo real da recusa.
 */
export function detalheErroMp(erro: unknown): string | null {
  if (erro instanceof MercadoPagoHttpError) {
    const partes: string[] = []
    try {
      const corpo = JSON.parse(erro.message) as {
        message?: unknown
        error?: unknown
        cause?: Array<{ code?: unknown; description?: unknown }> | null
      }
      if (corpo?.message) partes.push(String(corpo.message))
      if (corpo?.error && String(corpo.error) !== String(corpo.message ?? '')) partes.push(String(corpo.error))
      for (const c of Array.isArray(corpo?.cause) ? corpo.cause : []) {
        const texto = [c?.code, c?.description].filter((v) => v !== undefined && v !== null && v !== '').join(' ')
        if (texto) partes.push(texto)
      }
    } catch {
      if (erro.message.trim()) partes.push(erro.message.trim())
    }
    const detalhe = partes.join(' | ').replace(/\s+/g, ' ').slice(0, 240)
    return detalhe ? `HTTP ${erro.status}: ${detalhe}` : `HTTP ${erro.status}`
  }
  if (erro instanceof Error && erro.message.trim()) {
    return erro.message.trim().replace(/\s+/g, ' ').slice(0, 240)
  }
  return null
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
    if (
      corpo.includes('insufficient') ||
      corpo.includes('saldo') ||
      corpo.includes('balance') ||
      corpo.includes('enough available money') ||
      corpo.includes('120065')
    ) {
      return 'A conta Mercado Pago da casa não tem saldo disponível para devolver o valor. O dinheiro das vendas pode ainda estar "a liberar". Adicione saldo na conta (por exemplo, um Pix para ela) e tente de novo.'
    }
    if (corpo.includes('refunded') || corpo.includes('already')) {
      return 'Este pagamento já foi reembolsado no Mercado Pago.'
    }
    if (corpo.includes('expired') || corpo.includes('days') || corpo.includes('prazo')) {
      return 'O prazo do Mercado Pago para reembolsar este pagamento terminou. A devolução precisa ser feita por fora.'
    }
  }
  const detalhe = detalheErroMp(erro)
  const base = 'Não foi possível concluir o reembolso no Mercado Pago agora. Tente novamente em alguns minutos.'
  return detalhe ? `${base} Detalhe do Mercado Pago: ${detalhe}` : base
}
