import { serverSupabaseServiceRole } from '#supabase/server'

import { ehUuid } from '../../services/payments/payment-service'
import { MercadoPagoPaymentsProvider, valorConfere } from '../../services/payments/mercado-pago/mercado-pago-payments'
import { obterAccessTokenOrganizacao } from '../../services/payments/mercado-pago/mercado-pago-conexao'
import { ehAvisoIpn, validarAssinaturaMp } from '../../services/payments/mercado-pago/mercado-pago-signature'
import { sanitizarErroMercadoPago } from '../../services/payments/mercado-pago/mercado-pago-error'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'

/**
 * Webhook de pagamentos (multiempresa).
 *
 *  1. Assinatura: se MERCADO_PAGO_WEBHOOK_SECRET estiver definido e o header
 *     x-signature vier, ela precisa ser valida (senao 401). Avisos IPN nao sao
 *     assinados com ela e seguem sem essa checagem.
 *  2. Organizacao: pelo parametro `org` da notification_url ou, na falta dele,
 *     pelo `user_id` (conta do vendedor) informado no corpo.
 *  3. Nunca confia no payload: consulta o pagamento oficial com o token da
 *     organizacao e so confirma se a referencia pertence a ela e o valor confere.
 */
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig(event)
  const secret = String(config.mercadoPagoWebhookSecret ?? '')

  const query = getQuery(event)
  const body = await readBody<{ type?: string; action?: string; user_id?: string | number; data?: { id?: string } }>(
    event
  ).catch(() => ({}))
  const dataId = String(query['data.id'] ?? body?.data?.id ?? query.id ?? '') || null
  const tipo = String(query.type ?? query.topic ?? body?.type ?? '')

  const xSignature = getHeader(event, 'x-signature') ?? null
  const xRequestId = getHeader(event, 'x-request-id') ?? null

  // Outros topicos (merchant_order, etc.) sao ignorados antes da assinatura:
  // nao confirmam nada e nao devem gerar alerta.
  if (tipo && tipo !== 'payment') return { ok: true, ignorado: true }

  if (!dataId) return { ok: true, ignorado: true }

  // IPN nao e assinado com a assinatura secreta: segue sem checar (seguro,
  // o pagamento e conferido no Mercado Pago logo abaixo).
  if (secret && xSignature && !ehAvisoIpn(query)) {
    if (!validarAssinaturaMp({ xSignature, xRequestId, dataId }, secret)) {
      await alertarErroPagamento(event, {
        tipo: 'WEBHOOK',
        mensagem: 'Aviso do Mercado Pago recusado por assinatura inválida. Confira o MERCADO_PAGO_WEBHOOK_SECRET.',
        detalhe: {
          tipo,
          comOrg: Boolean(query.org),
          requestId: xRequestId
        },
        referencia: dataId
      })
      setResponseStatus(event, 401)
      return { error: 'ASSINATURA_INVALIDA' }
    }
  }

  const client = serverSupabaseServiceRole(event)

  let organizacaoId = String(query.org ?? '').trim()
  if (!ehUuid(organizacaoId)) {
    organizacaoId = ''
    const mpUserId = body?.user_id !== undefined && body?.user_id !== null ? String(body.user_id) : ''
    if (mpUserId) {
      const { data } = await client
        .from('organizacoes_mercado_pago')
        .select('organizacao_id')
        .eq('mp_user_id', mpUserId)
        .maybeSingle()
      organizacaoId = data?.organizacao_id ? String(data.organizacao_id) : ''
    }
  }
  if (!organizacaoId) {
    await alertarErroPagamento(event, {
      tipo: 'WEBHOOK',
      mensagem: 'Aviso de pagamento do Mercado Pago sem casa identificada; foi ignorado.',
      detalhe: { mpUserId: body?.user_id ?? null },
      referencia: dataId
    })
    return { ok: true, ignorado: true }
  }

  let accessToken: string | null
  try {
    accessToken = await obterAccessTokenOrganizacao(event, organizacaoId)
  } catch (erro) {
    await alertarErroPagamento(event, {
      tipo: 'TOKEN_MP',
      organizacaoId,
      mensagem: 'Aviso do Mercado Pago chegou, mas não foi possível ler a conexão da casa.',
      detalhe: { erro: erro instanceof Error ? erro.message : 'erro' },
      referencia: dataId
    })
    setResponseStatus(event, 503)
    return { error: 'PAGAMENTO_INDISPONIVEL' }
  }
  if (!accessToken) {
    await alertarErroPagamento(event, {
      tipo: 'CONTA_MP_DESCONECTADA',
      organizacaoId,
      mensagem: 'Aviso de pagamento do Mercado Pago chegou para uma casa sem conta conectada.',
      referencia: dataId
    })
    return { ok: true, ignorado: true }
  }

  let charge
  try {
    charge = await new MercadoPagoPaymentsProvider(accessToken).getCharge(dataId)
  } catch (erro) {
    // Pagamento nao pertence a esta conta ou provedor indisponivel: o MP reenviara.
    const mp = sanitizarErroMercadoPago(erro)
    await alertarErroPagamento(event, {
      tipo: 'WEBHOOK',
      organizacaoId,
      mensagem: `Não foi possível consultar no Mercado Pago o pagamento avisado${mp.httpStatus ? ` (HTTP ${mp.httpStatus})` : ''}. O Mercado Pago vai reenviar.`,
      detalhe: { ...mp },
      referencia: dataId
    })
    setResponseStatus(event, 502)
    return { error: 'CONSULTA_FALHOU' }
  }

  // Estorno ou contestacao (chargeback) feitos fora do painel: cancela o
  // pedido e os ingressos ainda nao usados. So age se for a transacao que
  // aprovou o pedido (o Pix cancelado quando o cartao foi aprovado e ignorado).
  const statusBruto = String(charge.providerStatus ?? '').toLowerCase()
  if ((statusBruto === 'refunded' || statusBruto === 'charged_back') && ehUuid(charge.externalReference)) {
    const contestacao = statusBruto === 'charged_back'
    const { data: estorno, error: erroEstorno } = await client.rpc('estornar_pedido_externo', {
      p_pagamento_id: charge.externalReference,
      p_transacao_id: charge.transactionId,
      p_tipo: contestacao ? 'CONTESTACAO' : 'REEMBOLSO'
    })
    if (erroEstorno) {
      await alertarErroPagamento(event, {
        tipo: 'CONTESTACAO',
        organizacaoId,
        mensagem: `Pagamento ${contestacao ? 'contestado' : 'estornado'} no Mercado Pago, mas o pedido não foi cancelado no sistema. O Mercado Pago vai reenviar.`,
        detalhe: { erro: erroEstorno.message },
        referencia: charge.externalReference
      })
      setResponseStatus(event, 500)
      return { error: 'ERRO_ESTORNO' }
    }
    const resultado = estorno as { resultado?: string; codigo_pedido?: string; ingressos_utilizados?: number } | null
    if (resultado?.resultado === 'cancelado') {
      const usados = Number(resultado.ingressos_utilizados ?? 0)
      await alertarErroPagamento(event, {
        tipo: 'CONTESTACAO',
        organizacaoId,
        mensagem: contestacao
          ? `Contestação (chargeback) no pedido ${resultado.codigo_pedido}: pedido e ingressos não usados foram cancelados.${usados ? ` ${usados} ingresso(s) já tinham entrado no evento.` : ''}`
          : `Pedido ${resultado.codigo_pedido} estornado direto no Mercado Pago: pedido e ingressos não usados foram cancelados.`,
        detalhe: { ...resultado, forma: charge.paymentMethodId ?? null },
        referencia: charge.externalReference
      })
    }
    return { ok: true }
  }

  if (charge.status !== 'APROVADO' || !ehUuid(charge.externalReference)) {
    return { ok: true }
  }

  const { data: pagamento } = await client
    .from('pagamentos')
    .select('id,organizacao_id,valor,status,transacao_id')
    .eq('id', charge.externalReference)
    .maybeSingle()

  if (!pagamento || String(pagamento.organizacao_id) !== organizacaoId) {
    return { ok: true, ignorado: true }
  }
  if (pagamento.status === 'APROVADO') {
    // Outra cobranca aprovada para um pedido ja pago (ex.: Pix e cartao): avisa.
    if (pagamento.transacao_id && String(pagamento.transacao_id) !== String(charge.transactionId)) {
      await alertarErroPagamento(event, {
        tipo: 'PAGAMENTO_DUPLICADO',
        organizacaoId,
        mensagem: 'Pedido já pago recebeu outro pagamento aprovado. Estorne a cobrança extra pelo Mercado Pago.',
        detalhe: { cobrancaExtra: charge.transactionId, cobrancaDoPedido: pagamento.transacao_id, forma: charge.paymentMethodId ?? null },
        referencia: String(pagamento.id)
      })
    }
    return { ok: true }
  }

  if (!valorConfere(charge.amount, pagamento.valor)) {
    console.error('[mercado-pago] webhook com valor divergente', {
      pagamentoId: pagamento.id,
      organizacaoId
    })
    await alertarErroPagamento(event, {
      tipo: 'VALOR_DIVERGENTE',
      organizacaoId,
      mensagem: 'Pagamento aprovado com valor diferente do pedido; não foi confirmado.',
      detalhe: { valorMp: charge.amount, valorPedido: Number(pagamento.valor) },
      referencia: String(pagamento.id)
    })
    return { ok: true, ignorado: true }
  }

  const { error } = await client.rpc('confirmar_pagamento', {
    p_pagamento_id: charge.externalReference,
    p_transaction_id: charge.transactionId,
    p_referencia_externa: charge.externalReference
  })
  if (error) {
    await alertarErroPagamento(event, {
      tipo: 'CONFIRMACAO',
      organizacaoId,
      mensagem: 'Pagamento aprovado no Mercado Pago, mas a confirmação no sistema falhou. O Mercado Pago vai reenviar.',
      detalhe: { erro: error.message },
      referencia: charge.externalReference
    })
    setResponseStatus(event, 500)
    return { error: 'ERRO_CONFIRMACAO' }
  }

  return { ok: true }
})
