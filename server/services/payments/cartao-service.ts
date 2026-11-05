import { getRequestIP, type H3Event } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

import {
  PaymentServiceError,
  confirmarPagamentoOficial,
  garantirPagamentoLogico,
  MSG_SEM_CONTA,
  obterCheckoutBackend,
  tokenDaOrganizacao,
  type CheckoutBackend
} from './payment-service'
import { MercadoPagoPaymentsProvider, montarNotificationUrl, valorConfere } from './mercado-pago/mercado-pago-payments'
import {
  MAX_PARCELAS,
  MAX_TENTATIVAS_CARTAO,
  mensagemRecusaCartao,
  montarPayloadCartao,
  statusTentativa,
  type DadosCartaoBrick,
  type MpCardPayment
} from './mercado-pago/mercado-pago-cartao'
import { reembolsarPagamentoMp } from './mercado-pago/mercado-pago-reembolso'
import { sanitizarErroMercadoPago, serializarLogErroMercadoPago } from './mercado-pago/mercado-pago-error'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'

export interface ConfigCartao {
  disponivel: boolean
  publicKey: string | null
  valor: number
  maxParcelas: number
  tentativasRestantes: number
  /** E-mail do pedido, para o formulario nao pedir de novo. */
  email: string | null
}

export interface ResultadoCartao {
  status: 'APROVADO' | 'RECUSADO' | 'PENDENTE'
  mensagem?: string
  tentativasRestantes?: number
}

function cartaoDisponivel(checkout: CheckoutBackend): boolean {
  return (
    checkout.cartao_ativo === true &&
    Boolean(checkout.mp_public_key) &&
    checkout.pedido_status === 'RESERVADO' &&
    checkout.pagamento_status !== 'APROVADO'
  )
}

/** O que a tela precisa para mostrar a aba "Cartao" (sem nada sensivel). */
export async function obterConfigCartao(event: H3Event, checkoutToken: string): Promise<ConfigCartao> {
  const checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  const restantes = Math.max(0, MAX_TENTATIVAS_CARTAO - Number(checkout.tentativas_cartao ?? 0))
  const disponivel = cartaoDisponivel(checkout) && restantes > 0
  return {
    disponivel,
    publicKey: disponivel ? (checkout.mp_public_key ?? null) : null,
    valor: Number(checkout.valor_total),
    maxParcelas: MAX_PARCELAS,
    tentativasRestantes: restantes,
    email: disponivel ? (checkout.comprador_email ?? null) : null
  }
}

function erroDaRpc(mensagem: string): PaymentServiceError {
  const m = mensagem.toLowerCase()
  if (m.includes('limite de tentativas')) {
    return new PaymentServiceError('LIMITE_TENTATIVAS', 'Limite de tentativas no cartão. Pague com Pix.', 429)
  }
  if (m.includes('expirada') || m.includes('nao esta disponivel')) {
    return new PaymentServiceError('DADOS_INVALIDOS', 'Este pedido não está mais disponível para pagamento.', 409)
  }
  if (m.includes('cartao nao liberado')) {
    return new PaymentServiceError('CARTAO_INDISPONIVEL', 'Pagamento com cartão indisponível neste evento.', 403)
  }
  return new PaymentServiceError('ERRO_INESPERADO', mensagem, 500)
}

/**
 * Pix aberto do mesmo pedido: confere antes de cobrar o cartao. Se o comprador
 * ja pagou o Pix, confirma por ele e nao cobra o cartao.
 */
async function pixJaPago(
  event: H3Event,
  checkoutToken: string,
  checkout: CheckoutBackend,
  provider: MercadoPagoPaymentsProvider
): Promise<boolean> {
  if (!checkout.cobranca_id) return false
  try {
    const pix = await provider.getCharge(checkout.cobranca_id)
    if (pix.status !== 'APROVADO') return false
    await confirmarPagamentoOficial(event, checkoutToken, checkout, pix)
    return true
  } catch {
    return false
  }
}

/**
 * Cartao aprovado: cancela o Pix aberto. Se nesses segundos o Pix foi pago,
 * o comprador pagou duas vezes: estorna o cartao e fica com o Pix.
 */
async function cancelarPixAberto(
  event: H3Event,
  checkout: CheckoutBackend,
  provider: MercadoPagoPaymentsProvider,
  accessToken: string,
  cartaoId: string
): Promise<'cancelado' | 'pix_pago'> {
  if (!checkout.cobranca_id) return 'cancelado'
  try {
    await provider.cancelPayment(checkout.cobranca_id)
    return 'cancelado'
  } catch {
    // Pix ja expirado/cancelado tambem cai aqui: so importa se foi pago.
  }
  try {
    const pix = await provider.getCharge(checkout.cobranca_id)
    if (pix.status !== 'APROVADO') return 'cancelado'
  } catch {
    return 'cancelado'
  }
  try {
    await reembolsarPagamentoMp(accessToken, cartaoId, `estorno-duplicado-${cartaoId}`)
    await alertarErroPagamento(event, {
      tipo: 'PAGAMENTO_DUPLICADO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Pedido ${checkout.codigo_pedido} foi pago no Pix e no cartão ao mesmo tempo. O cartão foi estornado e o pedido ficou com o Pix.`,
      referencia: checkout.pagamento_id
    })
  } catch (erro) {
    await alertarErroPagamento(event, {
      tipo: 'PAGAMENTO_DUPLICADO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Pedido ${checkout.codigo_pedido} foi pago no Pix e no cartão. O estorno automático do cartão FALHOU: estorne pelo Mercado Pago.`,
      detalhe: { cartaoId, ...sanitizarErroMercadoPago(erro) },
      referencia: checkout.pagamento_id
    })
  }
  return 'pix_pago'
}

export async function pagarComCartao(
  event: H3Event,
  checkoutToken: string,
  dados: DadosCartaoBrick
): Promise<ResultadoCartao> {
  let checkout = await obterCheckoutBackend(event, checkoutToken)
  if (!checkout) throw new PaymentServiceError('CHECKOUT_INVALIDO', 'Checkout não encontrado.', 404)
  if (checkout.pagamento_status === 'APROVADO') return { status: 'APROVADO' }
  if (checkout.pedido_status !== 'RESERVADO') {
    throw new PaymentServiceError('DADOS_INVALIDOS', 'Este pedido não está mais disponível para pagamento.', 409)
  }
  if (checkout.cartao_ativo !== true) {
    throw new PaymentServiceError('CARTAO_INDISPONIVEL', 'Pagamento com cartão indisponível neste evento.', 403)
  }

  const accessToken = await tokenDaOrganizacao(event, checkout)
  if (!accessToken) {
    await alertarErroPagamento(event, {
      tipo: 'CONTA_MP_DESCONECTADA',
      organizacaoId: checkout.organizacao_id,
      mensagem: 'Um comprador tentou pagar com cartão, mas a casa não tem Mercado Pago conectado.',
      referencia: checkout.codigo_pedido
    })
    throw new PaymentServiceError('PAGAMENTO_INDISPONIVEL', MSG_SEM_CONTA, 503)
  }

  checkout = await garantirPagamentoLogico(event, checkoutToken, checkout)
  const provider = new MercadoPagoPaymentsProvider(accessToken)

  if (await pixJaPago(event, checkoutToken, checkout, provider)) return { status: 'APROVADO' }

  const client = serverSupabaseServiceRole(event)
  const { data: inicio, error: erroInicio } = await client.rpc('iniciar_tentativa_cartao', { p_token: checkoutToken })
  if (erroInicio) throw erroDaRpc(erroInicio.message ?? '')
  const tentativa = inicio as { resultado: string; tentativa_id?: string; numero?: number }
  if (tentativa.resultado === 'ja_aprovado') return { status: 'APROVADO' }
  const tentativaId = String(tentativa.tentativa_id)
  const restantes = Math.max(0, MAX_TENTATIVAS_CARTAO - Number(tentativa.numero ?? MAX_TENTATIVAS_CARTAO))

  let payload
  try {
    const config = useRuntimeConfig(event)
    payload = montarPayloadCartao(
      {
        pagamentoId: checkout.pagamento_id as string,
        codigoPedido: checkout.codigo_pedido,
        valorTotal: Number(checkout.valor_total),
        valorTaxa: Number(checkout.valor_taxa_total ?? 0),
        eventoNome: checkout.evento_nome ?? 'Evento',
        quantidade: Number(checkout.quantidade ?? 1),
        compradorNome: checkout.comprador_nome ?? '',
        compradorTelefone: checkout.comprador_telefone ?? null,
        compradorEmail: checkout.comprador_email,
        notificationUrl: montarNotificationUrl(String(config.public.siteUrl ?? ''), checkout.organizacao_id),
        ipComprador: getRequestIP(event, { xForwardedFor: true }) ?? null
      },
      dados
    )
  } catch (erro) {
    await client.rpc('registrar_tentativa_cartao', {
      p_tentativa_id: tentativaId,
      p_mp_payment_id: null,
      p_status: 'ERRO',
      p_status_detail: erro instanceof Error ? erro.message : 'dados invalidos'
    })
    throw new PaymentServiceError('DADOS_CARTAO', 'Confira os dados do cartão e tente de novo.', 422)
  }

  let pagamento: MpCardPayment
  const deviceId = String(dados.deviceId ?? '').trim()
  try {
    const headers: Record<string, string> = { 'X-Idempotency-Key': tentativaId }
    if (deviceId) headers['X-meli-session-id'] = deviceId.slice(0, 200)
    pagamento = await provider.request<MpCardPayment>('/v1/payments', {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    })
  } catch (erro) {
    const mp = sanitizarErroMercadoPago(erro)
    console.error(
      '[mercado-pago] cartao falhou',
      serializarLogErroMercadoPago(
        { endpoint: 'POST /v1/payments', operation: 'createCardPayment', pagamentoId: checkout.pagamento_id, pedidoCodigo: checkout.codigo_pedido },
        erro
      )
    )
    await client.rpc('registrar_tentativa_cartao', {
      p_tentativa_id: tentativaId,
      p_mp_payment_id: null,
      p_status: 'ERRO',
      p_status_detail: `HTTP ${mp.httpStatus ?? '?'} ${mp.message ?? ''}`.trim()
    })
    // 400 = dado do cartao (token vencido, CPF invalido...): o comprador corrige.
    if (mp.httpStatus === 400) {
      throw new PaymentServiceError('DADOS_CARTAO', 'Confira os dados do cartão e tente de novo.', 422)
    }
    await alertarErroPagamento(event, {
      tipo: 'CARTAO',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Mercado Pago recusou o cartão do pedido ${checkout.codigo_pedido}${mp.httpStatus ? ` (HTTP ${mp.httpStatus})` : ''}${mp.message ? `: ${mp.message}` : '.'}`,
      detalhe: { ...mp },
      referencia: checkout.pagamento_id
    })
    throw new PaymentServiceError('PAGAMENTO_INDISPONIVEL', 'Não foi possível processar o cartão agora. Tente de novo ou pague com Pix.', 502)
  }

  const cartaoId = String(pagamento.id)
  const status = statusTentativa(pagamento.status)
  if (status !== 'APROVADA') {
    console.info('[mercado-pago] cartao nao aprovado', {
      pedidoCodigo: checkout.codigo_pedido,
      mpPaymentId: cartaoId,
      status: pagamento.status,
      statusDetail: pagamento.status_detail ?? null,
      comDeviceId: Boolean(deviceId),
      comDocumento: Boolean(payload.payer.identification),
      comIp: Boolean(payload.additional_info.ip_address)
    })
  }
  await client.rpc('registrar_tentativa_cartao', {
    p_tentativa_id: tentativaId,
    p_mp_payment_id: cartaoId,
    p_status: status,
    p_status_detail: pagamento.status_detail ?? null,
    p_parcelas: Number(pagamento.installments ?? payload.installments),
    p_bandeira: pagamento.payment_method_id ?? payload.payment_method_id,
    p_final: pagamento.card?.last_four_digits ?? null
  })

  if (status === 'RECUSADA') {
    return { status: 'RECUSADO', mensagem: mensagemRecusaCartao(pagamento.status_detail), tentativasRestantes: restantes }
  }
  if (status === 'PENDENTE') {
    // Com binary_mode nao deveria acontecer; webhook e cron confirmam depois.
    return { status: 'PENDENTE' }
  }

  if (!valorConfere(pagamento.transaction_amount, checkout.valor_total)) {
    await alertarErroPagamento(event, {
      tipo: 'VALOR_DIVERGENTE',
      organizacaoId: checkout.organizacao_id,
      mensagem: `Cartão aprovado do pedido ${checkout.codigo_pedido} com valor diferente do pedido; não foi confirmado.`,
      detalhe: { valorMp: pagamento.transaction_amount, valorPedido: Number(checkout.valor_total), cartaoId },
      referencia: checkout.pagamento_id
    })
    return { status: 'PENDENTE' }
  }

  if ((await cancelarPixAberto(event, checkout, provider, accessToken, cartaoId)) === 'pix_pago') {
    const pix = await provider.getCharge(checkout.cobranca_id as string)
    await confirmarPagamentoOficial(event, checkoutToken, checkout, pix)
    return { status: 'APROVADO' }
  }

  const { error } = await client.rpc('confirmar_pagamento', {
    p_pagamento_id: checkout.pagamento_id,
    p_transaction_id: cartaoId,
    p_referencia_externa: checkout.pagamento_id
  })
  if (error) {
    const atual = await obterCheckoutBackend(event, checkoutToken)
    if (atual?.pagamento_status !== 'APROVADO') {
      await alertarErroPagamento(event, {
        tipo: 'CONFIRMACAO',
        organizacaoId: checkout.organizacao_id,
        mensagem: `Cartão do pedido ${checkout.codigo_pedido} aprovado no Mercado Pago, mas não foi confirmado no sistema. O aviso do Mercado Pago vai tentar de novo.`,
        detalhe: { erro: error.message, cartaoId },
        referencia: checkout.pagamento_id
      })
      return { status: 'PENDENTE' }
    }
  }
  return { status: 'APROVADO' }
}
