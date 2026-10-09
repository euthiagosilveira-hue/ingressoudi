import type { H3Event } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

import type { Gz1PaymentStatus, PixCharge } from './payment-provider'
import { verificarCredencialDeTeste } from './mercado-pago/mercado-pago-client'
import { MercadoPagoProvider } from './mercado-pago/mercado-pago-provider'
import { deveAutoAprovarPixTeste, deveConfirmarPagamento, deveExpirarReserva, deveIgnorarFalhaConfirmacao } from './mercado-pago/mercado-pago-mapper'
import { serializarLogErroMercadoPago } from './mercado-pago/mercado-pago-error'

export type PaymentServiceErrorCode =
  | 'PAGAMENTO_INDISPONIVEL'
  | 'CHECKOUT_INVALIDO'
  | 'PROVIDER_CONFLITO'
  | 'DADOS_INVALIDOS'
  | 'ERRO_INESPERADO'

export class PaymentServiceError extends Error {
  code: PaymentServiceErrorCode
  status: number

  constructor(code: PaymentServiceErrorCode, message: string, status = 400) {
    super(message)
    this.name = 'PaymentServiceError'
    this.code = code
    this.status = status
  }
}

interface CheckoutBackend {
  pedido_id: string
  codigo_pedido: string
  comprador_email: string | null
  valor_total: number | string
  pedido_status: string
  reserva_expira_em: string
  pagamento_id: string | null
  provedor: string | null
  pagamento_status: string | null
  transacao_id: string | null
  cobranca_id: string | null
  referencia_externa: string | null
  pix_copia_cola: string | null
  pix_qr_code: string | null
  expira_em: string | null
}

export interface PixResponse {
  paymentId: string
  provider: 'MERCADO_PAGO'
  status: Gz1PaymentStatus
  pixCopyPaste: string | null
  pixQrCode: string | null
  expiresAt: string | null
}

export function ehUuid(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valor)
}

async function obterCheckoutBackend(event: H3Event, token: string): Promise<CheckoutBackend | null> {
  // serverSupabaseServiceRole e auto-importado pelo @nuxtjs/supabase
  const client = serverSupabaseServiceRole(event)
  const { data, error } = await client.rpc('obter_checkout_pagamento_backend', { p_token: token })
  if (error) throw new PaymentServiceError('ERRO_INESPERADO', error.message, 500)
  return (data as CheckoutBackend | null) ?? null
}

async function garantirPagamentoLogico(
  event: H3Event,
  token: string,
  checkout: CheckoutBackend
): Promise<CheckoutBackend> {
  // Pagamento ja no provedor correto: reutiliza.
  if (checkout.pagamento_id && checkout.provedor === 'MERCADO_PAGO') {
    return checkout
  }

  const client = serverSupabaseServiceRole(event)
  const { error } = await client.rpc('criar_pagamento_pendente_por_token', {
    p_token: token,
    p_provider: 'MERCADO_PAGO',
    p_transaction_id: null,
    p_charge_id: null,
    p_referencia_externa: null
  })
  if (error) {
    const msg = (error.message ?? '').toLowerCase()
    if (msg.includes('outro provedor') || msg.includes('ja possui pagamento')) {
      throw new PaymentServiceError(
        'PROVIDER_CONFLITO',
        'Este pedido possui um pagamento iniciado com outro provedor.',
        409
      )
    }
    throw new PaymentServiceError('ERRO_INESPERADO', error.message, 500)
  }

  const atualizado = await obterCheckoutBackend(event, token)
  if (!atualizado || !atualizado.pagamento_id) {
    throw new PaymentServiceError('ERRO_INESPERADO', 'Falha ao preparar o pagamento.', 500)
  }
  return atualizado
}

function minutosAte(iso: string): number {
  const alvo = Date.parse(iso)
  if (Number.isNaN(alvo)) return 30
  return Math.ceil((alvo - Date.now()) / 60000)
}

export async function criarPix(
  event: H3Event,
  checkoutToken: string,
  accessToken: string,
  autoApproveTestEnabled = false
): Promise<PixResponse> {
  let checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) {
    throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  }

  if (checkout.pedido_status === 'EXPIRADO' || checkout.pedido_status === 'CANCELADO') {
    throw new PaymentServiceError('DADOS_INVALIDOS', 'Este pedido não está disponível para pagamento.', 409)
  }

  checkout = await garantirPagamentoLogico(event, checkoutToken, checkout)

  if (checkout.pagamento_status === 'APROVADO') {
    return {
      paymentId: checkout.pagamento_id as string,
      provider: 'MERCADO_PAGO',
      status: 'APROVADO',
      pixCopyPaste: checkout.pix_copia_cola,
      pixQrCode: checkout.pix_qr_code,
      expiresAt: checkout.expira_em
    }
  }

  // Reaproveita cobranca ja registrada (idempotencia / refresh)
  if (checkout.cobranca_id && checkout.pix_copia_cola) {
    return {
      paymentId: checkout.pagamento_id as string,
      provider: 'MERCADO_PAGO',
      status: (checkout.pagamento_status as Gz1PaymentStatus) ?? 'PENDENTE',
      pixCopyPaste: checkout.pix_copia_cola,
      pixQrCode: checkout.pix_qr_code,
      expiresAt: checkout.expira_em
    }
  }

  const email = (checkout.comprador_email ?? '').trim()
  if (!email) {
    throw new PaymentServiceError('DADOS_INVALIDOS', 'E-mail do comprador ausente.', 422)
  }

  const provider = new MercadoPagoProvider(accessToken)
  const credencialDeTeste = autoApproveTestEnabled
    ? await verificarCredencialDeTeste(accessToken)
    : false
  let charge: PixCharge
  try {
    charge = await provider.createPixCharge({
      amount: Number(checkout.valor_total),
      externalReference: checkout.pagamento_id as string,
      payerEmail: email,
      expirationMinutes: minutosAte(checkout.reserva_expira_em),
      idempotencyKey: checkout.pagamento_id as string,
      autoApproveTestPix: deveAutoAprovarPixTeste(autoApproveTestEnabled, credencialDeTeste)
    })
  } catch (erro) {
    // Log tecnico sanitizado e serializado (sem token/headers/corpo bruto).
    // Serializar garante que errors[].details apareca expandido no Runtime Log.
    console.error(
      '[mercado-pago] createPixCharge failed',
      serializarLogErroMercadoPago(
        {
          endpoint: 'POST /v1/orders',
          operation: 'createOrder',
          pagamentoId: checkout.pagamento_id,
          pedidoCodigo: checkout.codigo_pedido
        },
        erro
      )
    )
    throw erro
  }

  const client = serverSupabaseServiceRole(event)
  const { error } = await client.rpc('registrar_cobranca_externa', {
    p_pagamento_id: checkout.pagamento_id,
    p_provider: 'MERCADO_PAGO',
    p_transacao_id: charge.transactionId,
    p_cobranca_id: charge.chargeId,
    p_referencia_externa: charge.externalReference,
    p_pix_copia_cola: charge.pixCopyPaste,
    p_pix_qr_code: charge.pixQrCode
  })
  if (error) throw new PaymentServiceError('ERRO_INESPERADO', error.message, 500)

  return {
    paymentId: checkout.pagamento_id as string,
    provider: 'MERCADO_PAGO',
    status: charge.status,
    pixCopyPaste: charge.pixCopyPaste,
    pixQrCode: charge.pixQrCode,
    expiresAt: checkout.expira_em
  }
}

/**
 * Caminho de recuperacao: quando a Order oficial ja esta APROVADA mas o
 * pagamento interno ainda nao, confirma pelo service_role (idempotente).
 * Seguro sob concorrencia com o webhook: se a RPC falhar mas o pagamento ja
 * estiver APROVADO, tratamos como sucesso; caso contrario, erro controlado.
 * Usado pelo GET /api/payments/status (abrir/atualizar a tela de pagamento).
 */
async function confirmarPagamentoOficial(
  event: H3Event,
  checkoutToken: string,
  checkout: CheckoutBackend,
  charge: PixCharge
): Promise<boolean> {
  if (!deveConfirmarPagamento(charge.status, checkout.pagamento_status)) return false

  const client = serverSupabaseServiceRole(event)
  const { error } = await client.rpc('confirmar_pagamento', {
    p_pagamento_id: checkout.pagamento_id,
    p_transaction_id: charge.transactionId,
    p_referencia_externa: charge.externalReference || (checkout.pagamento_id as string)
  })

  if (error) {
    const atual = await obterCheckoutBackend(event, checkoutToken)
    if (deveIgnorarFalhaConfirmacao(atual?.pagamento_status)) return true
    throw new PaymentServiceError('ERRO_INESPERADO', 'Não foi possível confirmar o pagamento.', 500)
  }

  return true
}

export async function consultarStatus(
  event: H3Event,
  checkoutToken: string,
  accessToken: string
): Promise<{ status: Gz1PaymentStatus }> {
  const checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) {
    throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  }

  // Pedido ja finalizado (nao aprovado) reflete o estado definitivo.
  if (
    (checkout.pedido_status === 'EXPIRADO' || checkout.pedido_status === 'CANCELADO') &&
    checkout.pagamento_status !== 'APROVADO'
  ) {
    return { status: checkout.pedido_status === 'CANCELADO' ? 'CANCELADO' : 'EXPIRADO' }
  }

  let status: Gz1PaymentStatus = (checkout.pagamento_status as Gz1PaymentStatus) ?? 'PENDENTE'

  // 1) Reconcilia com o provedor ANTES de qualquer expiracao: nunca perder um
  //    pagamento aprovado no limite da reserva. Se o provedor falhar, mantemos
  //    o status interno e seguimos para a expiracao (fonte de verdade e o banco).
  if (checkout.cobranca_id && accessToken) {
    try {
      const provider = new MercadoPagoProvider(accessToken)
      const charge = await provider.getCharge(checkout.cobranca_id)
      const confirmou = await confirmarPagamentoOficial(event, checkoutToken, checkout, charge)

      if (confirmou) {
        const atualizado = await obterCheckoutBackend(event, checkoutToken)
        if (atualizado?.pagamento_status === 'APROVADO') return { status: 'APROVADO' }
      }

      status = charge.status
    } catch {
      // Provedor indisponivel/ordem nao encontrada: nao bloqueia a expiracao.
    }
  }

  // 2) Somente expira se NAO estiver aprovado e a reserva realmente venceu.
  if (
    status !== 'APROVADO' &&
    deveExpirarReserva(checkout.reserva_expira_em, checkout.pedido_status, checkout.pagamento_status, Date.now())
  ) {
    const client = serverSupabaseServiceRole(event)
    const { data, error } = await client.rpc('expirar_reserva', { p_pedido_id: checkout.pedido_id })
    if (!error) {
      const resultado = (data as { resultado?: string; status?: string } | null) ?? null
      if (resultado?.resultado === 'expirado' || resultado?.status === 'EXPIRADO') {
        return { status: 'EXPIRADO' }
      }
    }
  }

  return { status }
}
