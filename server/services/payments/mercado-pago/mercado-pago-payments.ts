import type { CreatePixChargeInput, Gz1PaymentStatus, PaymentProvider, PixCharge } from '../payment-provider.ts'
import { MercadoPagoHttpError } from './mercado-pago-client.ts'

/**
 * Pix via API de Payments (/v1/payments) usando o access_token da conta
 * conectada da organizacao (marketplace). A comissao da plataforma vai em
 * `application_fee` (documentacao de marketplace do Checkout Transparente).
 * Modulo sem auto-imports do Nuxt (testavel com node --test).
 */

const BASE_URL = 'https://api.mercadopago.com'
const MINUTOS_MINIMOS = 30

export interface MpPayment {
  id: number | string
  status: string
  status_detail?: string | null
  external_reference?: string | null
  transaction_amount?: number | null
  application_fee?: number | null
  date_of_expiration?: string | null
  point_of_interaction?: {
    transaction_data?: {
      qr_code?: string | null
      qr_code_base64?: string | null
      ticket_url?: string | null
    } | null
  } | null
}

export interface MpCreatePaymentRequest {
  transaction_amount: number
  description: string
  payment_method_id: 'pix'
  external_reference: string
  date_of_expiration: string
  payer: { email: string; first_name?: string }
  application_fee?: number
  notification_url?: string
}

function arredondar(valor: number): number {
  return Math.round(valor * 100) / 100
}

/** ISO 8601 no fuso de Brasilia (-03:00), formato aceito pelo Mercado Pago. */
export function isoBrasilia(ms: number): string {
  const deslocado = new Date(ms - 3 * 60 * 60 * 1000)
  return deslocado.toISOString().replace('Z', '-03:00')
}

export function montarPayloadPagamentoPix(input: CreatePixChargeInput, agoraMs: number): MpCreatePaymentRequest {
  const minutos = Math.max(MINUTOS_MINIMOS, Math.ceil(input.expirationMinutes))
  const payer: MpCreatePaymentRequest['payer'] = { email: input.payerEmail }
  if (input.autoApproveTestPix) payer.first_name = 'APRO'

  const payload: MpCreatePaymentRequest = {
    transaction_amount: arredondar(input.amount),
    description: input.description ?? 'Ingressos',
    payment_method_id: 'pix',
    external_reference: input.externalReference,
    date_of_expiration: isoBrasilia(agoraMs + minutos * 60 * 1000),
    payer
  }

  const taxa = arredondar(input.applicationFee ?? 0)
  if (taxa > 0) {
    if (taxa > payload.transaction_amount) {
      throw new Error('Comissao maior que o valor do pagamento.')
    }
    payload.application_fee = taxa
  }

  if (input.notificationUrl) payload.notification_url = input.notificationUrl
  return payload
}

/** Status da API de Payments -> status interno. */
export function mapMpPaymentStatus(status: string, statusDetail?: string | null): Gz1PaymentStatus {
  const s = (status || '').toLowerCase()
  const d = (statusDetail || '').toLowerCase()
  if (s === 'approved') return 'APROVADO'
  if (s === 'refunded' || d === 'refunded' || d === 'partially_refunded') return 'REEMBOLSADO'
  if (s === 'charged_back') return 'CANCELADO'
  if (s === 'cancelled' || s === 'canceled') return d === 'expired' ? 'EXPIRADO' : 'CANCELADO'
  if (s === 'rejected') return 'REJEITADO'
  return 'PENDENTE'
}

export function mapMpPaymentToCharge(payment: MpPayment): PixCharge {
  const dados = payment.point_of_interaction?.transaction_data ?? null
  const id = payment.id === undefined || payment.id === null ? null : String(payment.id)
  return {
    provider: 'MERCADO_PAGO',
    transactionId: id,
    chargeId: id,
    externalReference: payment.external_reference ?? '',
    status: mapMpPaymentStatus(payment.status, payment.status_detail),
    pixCopyPaste: dados?.qr_code ?? null,
    pixQrCode: dados?.qr_code_base64 ?? null,
    expiresAt: payment.date_of_expiration ?? null,
    amount: typeof payment.transaction_amount === 'number' ? payment.transaction_amount : null
  }
}

export class MercadoPagoPaymentsProvider implements PaymentProvider {
  readonly name = 'MERCADO_PAGO' as const
  private readonly accessToken: string

  constructor(accessToken: string) {
    this.accessToken = accessToken
  }

  private async request<T>(path: string, init: RequestInit): Promise<T> {
    const response = await fetch(`${BASE_URL}${path}`, {
      ...init,
      headers: {
        accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.accessToken}`,
        ...(init.headers ?? {})
      }
    })
    if (!response.ok) {
      const texto = await response.text().catch(() => '')
      throw new MercadoPagoHttpError(
        response.status,
        texto.slice(0, 2000),
        response.headers.get('x-request-id')
      )
    }
    return (await response.json()) as T
  }

  async createPixCharge(input: CreatePixChargeInput): Promise<PixCharge> {
    const payload = montarPayloadPagamentoPix(input, Date.now())
    const payment = await this.request<MpPayment>('/v1/payments', {
      method: 'POST',
      headers: { 'X-Idempotency-Key': input.idempotencyKey },
      body: JSON.stringify(payload)
    })
    return mapMpPaymentToCharge(payment)
  }

  async getCharge(chargeId: string): Promise<PixCharge> {
    const payment = await this.request<MpPayment>(`/v1/payments/${encodeURIComponent(chargeId)}`, {
      method: 'GET'
    })
    return mapMpPaymentToCharge(payment)
  }
}

/**
 * URL de notificacao por cobranca, identificando a organizacao.
 * So e enviada quando a URL publica e https (o Mercado Pago exige).
 */
export function montarNotificationUrl(siteUrl: string | null | undefined, organizacaoId: string): string | undefined {
  const base = String(siteUrl ?? '').trim().replace(/\/+$/, '')
  if (!base.startsWith('https://')) return undefined
  return `${base}/api/webhooks/mercadopago?org=${encodeURIComponent(organizacaoId)}`
}

/** Confere o valor cobrado no provedor com o valor esperado (centavos). */
export function valorConfere(cobrado: number | null | undefined, esperado: number | string | null | undefined): boolean {
  if (typeof cobrado !== 'number' || Number.isNaN(cobrado)) return false
  const alvo = Number(esperado)
  if (Number.isNaN(alvo)) return false
  return Math.round(cobrado * 100) === Math.round(alvo * 100)
}
