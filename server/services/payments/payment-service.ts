import type { H3Event } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

import type { Gz1PaymentStatus, PixCharge } from './payment-provider'
import { verificarCredencialDeTeste } from './mercado-pago/mercado-pago-client'
import {
  fimReservaParaPix,
  MercadoPagoPaymentsProvider,
  minutosValidadePix,
  montarNotificationUrl,
  valorConfere
} from './mercado-pago/mercado-pago-payments'
import { obterAccessTokenOrganizacao } from './mercado-pago/mercado-pago-conexao'
import { deveAutoAprovarPixTeste, deveConfirmarPagamento, deveExpirarReserva, deveIgnorarFalhaConfirmacao } from './mercado-pago/mercado-pago-mapper'
import { sanitizarErroMercadoPago, serializarLogErroMercadoPago } from './mercado-pago/mercado-pago-error'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'

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
  valor_taxa_total: number | string | null
  organizacao_id: string
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

const MSG_SEM_CONTA =
  'O organizador deste evento ainda não conectou o Mercado Pago. Tente novamente mais tarde.'

async function obterCheckoutBackend(event: H3Event, token: string): Promise<CheckoutBackend | null> {
  const client = serverSupabaseServiceRole(event)
  const { data, error } = await client.rpc('obter_checkout_pagamento_backend', { p_token: token })
  if (error) throw new PaymentServiceError('ERRO_INESPERADO', error.message, 500)
  return (data as CheckoutBackend | null) ?? null
}

/** Token da conta Mercado Pago da organizacao dona do pedido (ou null). */
async function tokenDaOrganizacao(event: H3Event, checkout: CheckoutBackend): Promise<string | null> {
  if (!checkout.organizacao_id) return null
  try {
    return await obterAccessTokenOrganizacao(event, checkout.organizacao_id)
  } catch (erro) {
    await alertarErroPagamento(event, {
      tipo: 'TOKEN_MP',
      organizacaoId: checkout.organizacao_id,
      mensagem: 'Não foi possível ler a conexão Mercado Pago da casa.',
      detalhe: { erro: erro instanceof Error ? erro.message : 'erro' },
      referencia: checkout.codigo_pedido
    })
    throw new PaymentServiceError('PAGAMENTO_INDISPONIVEL', 'Pagamento Pix temporariamente indisponível.', 503)
  }
}

async function garantirPagamentoLogico(
  event: H3Event,
  token: string,
  checkout: CheckoutBackend
): Promise<CheckoutBackend> {
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

/**
 * Estende a reserva (e o prazo exibido ao comprador) ate o fim do Pix. Falha
 * aqui nao impede o pagamento: se o Pix for pago depois da reserva, a
 * confirmacao ainda emite os ingressos (confirmar_pagamento).
 */
async function estenderReservaAtePix(
  event: H3Event,
  pagamentoId: string,
  fimIso: string,
  expiraAtual: string | null
): Promise<string | null> {
  const client = serverSupabaseServiceRole(event)
  const { data, error } = await client.rpc('estender_reserva_pix', {
    p_pagamento_id: pagamentoId,
    p_expira_em: fimIso
  })
  if (error) {
    console.error('[pagamentos] estender_reserva_pix falhou', { pagamentoId, erro: error.message })
    return expiraAtual
  }
  const resultado = data as { reserva_expira_em?: string | null } | null
  return resultado?.reserva_expira_em ?? expiraAtual
}

function minutosAte(iso: string): number {
  const alvo = Date.parse(iso)
  if (Number.isNaN(alvo)) return 30
  return Math.ceil((alvo - Date.now()) / 60000)
}

export async function criarPix(
  event: H3Event,
  checkoutToken: string,
  autoApproveTestEnabled = false
): Promise<PixResponse> {
  let checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) {
    throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  }

  if (checkout.pedido_status === 'EXPIRADO' || checkout.pedido_status === 'CANCELADO') {
    throw new PaymentServiceError('DADOS_INVALIDOS', 'Este pedido não está disponível para pagamento.', 409)
  }

  // Reaproveita estados ja resolvidos sem exigir conta conectada.
  if (checkout.pagamento_id && checkout.provedor === 'MERCADO_PAGO') {
    if (checkout.pagamento_status === 'APROVADO' || (checkout.cobranca_id && checkout.pix_copia_cola)) {
      return {
        paymentId: checkout.pagamento_id,
        provider: 'MERCADO_PAGO',
        status: (checkout.pagamento_status as Gz1PaymentStatus) ?? 'PENDENTE',
        pixCopyPaste: checkout.pix_copia_cola,
        pixQrCode: checkout.pix_qr_code,
        expiresAt: checkout.expira_em
      }
    }
  }

  const accessToken = await tokenDaOrganizacao(event, checkout)
  if (!accessToken) {
    await alertarErroPagamento(event, {
      tipo: 'CONTA_MP_DESCONECTADA',
      organizacaoId: checkout.organizacao_id,
      mensagem: 'Um comprador tentou pagar com Pix, mas a casa não tem Mercado Pago conectado.',
      referencia: checkout.codigo_pedido
    })
    throw new PaymentServiceError('PAGAMENTO_INDISPONIVEL', MSG_SEM_CONTA, 503)
  }

  const email = (checkout.comprador_email ?? '').trim()
  if (!email) {
    throw new PaymentServiceError('DADOS_INVALIDOS', 'E-mail do comprador ausente.', 422)
  }

  checkout = await garantirPagamentoLogico(event, checkoutToken, checkout)

  if (checkout.pagamento_status === 'APROVADO' || (checkout.cobranca_id && checkout.pix_copia_cola)) {
    return {
      paymentId: checkout.pagamento_id as string,
      provider: 'MERCADO_PAGO',
      status: (checkout.pagamento_status as Gz1PaymentStatus) ?? 'PENDENTE',
      pixCopyPaste: checkout.pix_copia_cola,
      pixQrCode: checkout.pix_qr_code,
      expiresAt: checkout.expira_em
    }
  }

  const config = useRuntimeConfig(event)
  const provider = new MercadoPagoPaymentsProvider(accessToken)
  const credencialDeTeste = autoApproveTestEnabled
    ? await verificarCredencialDeTeste(accessToken)
    : false

  // O Pix vale no minimo 30 minutos (regra do Mercado Pago), entao a reserva
  // e estendida ate o fim da validade do Pix logo apos registrar a cobranca.
  const inicioPixMs = Date.now()
  const minutosPix = minutosValidadePix(minutosAte(checkout.reserva_expira_em))

  let charge: PixCharge
  try {
    charge = await provider.createPixCharge({
      amount: Number(checkout.valor_total),
      applicationFee: Number(checkout.valor_taxa_total ?? 0),
      description: `Pedido ${checkout.codigo_pedido}`,
      notificationUrl: montarNotificationUrl(String(config.public.siteUrl ?? ''), checkout.organizacao_id),
      externalReference: checkout.pagamento_id as string,
      payerEmail: email,
      expirationMinutes: minutosPix,
      idempotencyKey: checkout.pagamento_id as string,
      autoApproveTestPix: deveAutoAprovarPixTeste(autoApproveTestEnabled, credencialDeTeste)
    })
  } catch (erro) {
    console.error(
      '[mercado-pago] createPixCharge failed',
      serializarLogErroMercadoPago(
        {
          endpoint: 'POST /v1/payments',
          operation: 'createPayment',
          pagamentoId: checkout.pagamento_id,
          pedidoCodigo: checkout.codigo_pedido
        },
        erro
      )
    )
    const mp = sanitizarErroMercadoPago(erro)
    await alertarErroPagamento(event, {
      tipo: 'PIX_CRIACAO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Mercado Pago recusou o Pix do pedido ${checkout.codigo_pedido}${mp.httpStatus ? ` (HTTP ${mp.httpStatus})` : ''}${mp.message ? `: ${mp.message}` : '.'}`,
      detalhe: { ...mp },
      referencia: checkout.pagamento_id
    })
    throw new PaymentServiceError('PAGAMENTO_INDISPONIVEL', 'Não foi possível gerar o Pix. Tente novamente.', 502)
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
  if (error) {
    await alertarErroPagamento(event, {
      tipo: 'PIX_CRIACAO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Pix do pedido ${checkout.codigo_pedido} foi criado no Mercado Pago, mas não foi gravado no sistema.`,
      detalhe: { erro: error.message, cobrancaId: charge.chargeId },
      referencia: checkout.pagamento_id
    })
    throw new PaymentServiceError('ERRO_INESPERADO', error.message, 500)
  }

  const expiresAt = await estenderReservaAtePix(
    event,
    checkout.pagamento_id as string,
    fimReservaParaPix(inicioPixMs, minutosPix),
    checkout.expira_em
  )

  return {
    paymentId: checkout.pagamento_id as string,
    provider: 'MERCADO_PAGO',
    status: charge.status,
    pixCopyPaste: charge.pixCopyPaste,
    pixQrCode: charge.pixQrCode,
    expiresAt
  }
}

/**
 * Recuperacao: pagamento oficial APROVADO mas interno ainda nao. Confirma pelo
 * service_role (idempotente), somente se a referencia e o valor conferem.
 */
async function confirmarPagamentoOficial(
  event: H3Event,
  checkoutToken: string,
  checkout: CheckoutBackend,
  charge: PixCharge
): Promise<boolean> {
  if (!deveConfirmarPagamento(charge.status, checkout.pagamento_status)) return false
  if (charge.externalReference && charge.externalReference !== checkout.pagamento_id) return false
  if (!valorConfere(charge.amount, checkout.valor_total)) {
    console.error('[mercado-pago] valor divergente na confirmacao', {
      pagamentoId: checkout.pagamento_id,
      pedidoCodigo: checkout.codigo_pedido
    })
    await alertarErroPagamento(event, {
      tipo: 'VALOR_DIVERGENTE',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Pix aprovado do pedido ${checkout.codigo_pedido} com valor diferente do pedido; não foi confirmado.`,
      detalhe: { valorMp: charge.amount, valorPedido: Number(checkout.valor_total) },
      referencia: checkout.pagamento_id
    })
    return false
  }

  const client = serverSupabaseServiceRole(event)
  const { error } = await client.rpc('confirmar_pagamento', {
    p_pagamento_id: checkout.pagamento_id,
    p_transaction_id: charge.transactionId,
    p_referencia_externa: charge.externalReference || (checkout.pagamento_id as string)
  })

  if (error) {
    const atual = await obterCheckoutBackend(event, checkoutToken)
    if (deveIgnorarFalhaConfirmacao(atual?.pagamento_status)) return true
    await alertarErroPagamento(event, {
      tipo: 'CONFIRMACAO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Pix do pedido ${checkout.codigo_pedido} está aprovado no Mercado Pago, mas não foi confirmado no sistema.`,
      detalhe: { erro: error.message },
      referencia: checkout.pagamento_id
    })
    throw new PaymentServiceError('ERRO_INESPERADO', 'Não foi possível confirmar o pagamento.', 500)
  }

  return true
}

export async function consultarStatus(
  event: H3Event,
  checkoutToken: string
): Promise<{ status: Gz1PaymentStatus }> {
  const checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) {
    throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  }

  if (
    (checkout.pedido_status === 'EXPIRADO' || checkout.pedido_status === 'CANCELADO') &&
    checkout.pagamento_status !== 'APROVADO'
  ) {
    // Pix pago depois de a reserva vencer: confirma mesmo assim (o comprador pagou).
    if (checkout.pedido_status === 'EXPIRADO' && checkout.cobranca_id) {
      try {
        const accessToken = await tokenDaOrganizacao(event, checkout)
        if (accessToken) {
          const charge = await new MercadoPagoPaymentsProvider(accessToken).getCharge(checkout.cobranca_id)
          if (await confirmarPagamentoOficial(event, checkoutToken, checkout, charge)) {
            const atualizado = await obterCheckoutBackend(event, checkoutToken)
            if (atualizado?.pagamento_status === 'APROVADO') return { status: 'APROVADO' }
          }
        }
      } catch {
        // Provedor indisponivel: mantem expirado; o webhook ainda pode confirmar.
      }
    }
    return { status: checkout.pedido_status === 'CANCELADO' ? 'CANCELADO' : 'EXPIRADO' }
  }

  let status: Gz1PaymentStatus = (checkout.pagamento_status as Gz1PaymentStatus) ?? 'PENDENTE'

  // 1) Reconcilia com o provedor ANTES de expirar: nunca perder um pagamento
  //    aprovado no limite da reserva.
  if (checkout.cobranca_id && status !== 'APROVADO') {
    try {
      const accessToken = await tokenDaOrganizacao(event, checkout)
      if (accessToken) {
        const provider = new MercadoPagoPaymentsProvider(accessToken)
        const charge = await provider.getCharge(checkout.cobranca_id)
        const confirmou = await confirmarPagamentoOficial(event, checkoutToken, checkout, charge)

        if (confirmou) {
          const atualizado = await obterCheckoutBackend(event, checkoutToken)
          if (atualizado?.pagamento_status === 'APROVADO') return { status: 'APROVADO' }
        }

        if (charge.status !== 'APROVADO') status = charge.status
      }
    } catch {
      // Provedor indisponivel: nao bloqueia a expiracao (fonte de verdade e o banco).
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
