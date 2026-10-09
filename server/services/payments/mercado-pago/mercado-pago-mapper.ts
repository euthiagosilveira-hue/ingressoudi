import type { CreatePixChargeInput, Gz1PaymentStatus, PixCharge } from '../payment-provider'
import type { MpCreateOrderRequest, MpOrder, MpTransactionPayment } from './mercado-pago-types'

const MINUTOS_MINIMOS = 30

function formatarValor(valor: number): string {
  return valor.toFixed(2)
}

function duracaoIso(minutos: number): string {
  return `PT${Math.max(MINUTOS_MINIMOS, Math.ceil(minutos))}M`
}

/**
 * Fail-safe: so auto-aprova quando a flag de teste esta ligada E a credencial
 * foi confirmada como de teste. Qualquer duvida => false.
 */
export function deveAutoAprovarPixTeste(
  autoApproveHabilitado: boolean,
  credencialDeTeste: boolean
): boolean {
  return autoApproveHabilitado === true && credencialDeTeste === true
}

/**
 * Caminho de recuperacao: confirma apenas se a Order oficial esta aprovada
 * e o pagamento interno ainda nao esta APROVADO (idempotente).
 */
export function deveConfirmarPagamento(
  chargeStatus: Gz1PaymentStatus,
  pagamentoStatus?: string | null
): boolean {
  return chargeStatus === 'APROVADO' && pagamentoStatus !== 'APROVADO'
}

/**
 * Condicao de corrida: se apos a falha o pagamento interno ja esta APROVADO
 * (ex.: webhook concorrente confirmou), tratamos como sucesso.
 */
export function deveIgnorarFalhaConfirmacao(pagamentoStatus?: string | null): boolean {
  return pagamentoStatus === 'APROVADO'
}

/**
 * Decide se a reserva deve ser expirada. Nunca expira pagamento aprovado;
 * apenas pedidos ainda RESERVADO cujo prazo ja passou (relogio do servidor).
 */
export function deveExpirarReserva(
  reservaExpiraEm: string | null | undefined,
  pedidoStatus: string | null | undefined,
  pagamentoStatus: string | null | undefined,
  agoraMs: number
): boolean {
  if (pedidoStatus !== 'RESERVADO') return false
  if (pagamentoStatus === 'APROVADO') return false
  if (!reservaExpiraEm) return false
  const limite = Date.parse(reservaExpiraEm)
  if (Number.isNaN(limite)) return false
  return agoraMs >= limite
}

/** Monta o payload da Order Pix (Orders API). */
export function montarPayloadOrderPix(input: CreatePixChargeInput): MpCreateOrderRequest {
  const amount = formatarValor(input.amount)
  const payer: { email: string; first_name?: string } = { email: input.payerEmail }
  if (input.autoApproveTestPix) payer.first_name = 'APRO'

  return {
    type: 'online',
    total_amount: amount,
    external_reference: input.externalReference,
    processing_mode: 'automatic',
    transactions: {
      payments: [
        {
          amount,
          payment_method: { id: 'pix', type: 'bank_transfer' },
          expiration_time: duracaoIso(input.expirationMinutes)
        }
      ]
    },
    payer
  }
}

/**
 * Mapeia status/status_detail do Mercado Pago para o status interno GZ1.
 * Fonte oficial: docs/checkout-api-orders/payment-management/status/transaction-status
 */
export function mapMpStatus(status: string, statusDetail?: string | null): Gz1PaymentStatus {
  const s = (status || '').toLowerCase()
  const d = (statusDetail || '').toLowerCase()

  if (s === 'processed' && d === 'accredited') return 'APROVADO'
  if (s === 'processed' && (d === 'refunded' || d === 'partially_refunded')) return 'REEMBOLSADO'
  if (s === 'refunded' || d === 'refunded') return 'REEMBOLSADO'
  if (s === 'charged_back') return 'CANCELADO'
  if (s === 'canceled' || d === 'canceled') return 'CANCELADO'
  if (s === 'expired' || d === 'expired') return 'EXPIRADO'
  if (s === 'failed') return 'REJEITADO'
  return 'PENDENTE'
}

function primeiroPagamento(order: MpOrder): MpTransactionPayment | null {
  const payments = order.transactions?.payments
  if (!payments || payments.length === 0) return null
  return payments[0]
}

export function mapMpOrderToCharge(order: MpOrder): PixCharge {
  const pagamento = primeiroPagamento(order)
  const metodo = pagamento?.payment_method ?? null
  const status = mapMpStatus(pagamento?.status ?? order.status, pagamento?.status_detail ?? order.status_detail)

  return {
    provider: 'MERCADO_PAGO',
    transactionId: pagamento?.id ?? null,
    chargeId: order.id,
    externalReference: order.external_reference ?? '',
    status,
    pixCopyPaste: metodo?.qr_code ?? null,
    pixQrCode: metodo?.qr_code_base64 ?? null,
    expiresAt: null
  }
}
