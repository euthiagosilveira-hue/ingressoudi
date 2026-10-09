import type { MpCreateOrderRequest, MpOrder } from './mercado-pago-types'

const BASE_URL = 'https://api.mercadopago.com'

/**
 * Confirma via API oficial se a credencial pertence a um usuario de teste.
 * Sinal robusto: GET /users/me retorna tags contendo "test_user".
 * Fail-safe: qualquer erro/duvida => false (nunca trata como teste).
 */
export async function verificarCredencialDeTeste(accessToken: string): Promise<boolean> {
  try {
    const response = await fetch(`${BASE_URL}/users/me`, {
      headers: { accept: 'application/json', Authorization: `Bearer ${accessToken}` }
    })
    if (!response.ok) return false
    const usuario = (await response.json()) as { tags?: unknown }
    const tags = Array.isArray(usuario?.tags) ? usuario.tags : []
    return tags.includes('test_user')
  } catch {
    return false
  }
}

export class MercadoPagoHttpError extends Error {
  status: number
  requestId: string | null

  constructor(status: number, message: string, requestId: string | null = null) {
    super(message)
    this.name = 'MercadoPagoHttpError'
    this.status = status
    this.requestId = requestId
  }
}

export class MercadoPagoClient {
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
      // Captura SOMENTE o x-request-id (para suporte MP). Nunca outros headers.
      throw new MercadoPagoHttpError(
        response.status,
        texto.slice(0, 2000),
        response.headers.get('x-request-id')
      )
    }

    return (await response.json()) as T
  }

  createOrder(payload: MpCreateOrderRequest, idempotencyKey: string): Promise<MpOrder> {
    return this.request<MpOrder>('/v1/orders', {
      method: 'POST',
      headers: { 'X-Idempotency-Key': idempotencyKey },
      body: JSON.stringify(payload)
    })
  }

  getOrder(orderId: string): Promise<MpOrder> {
    return this.request<MpOrder>(`/v1/orders/${encodeURIComponent(orderId)}`, { method: 'GET' })
  }
}
