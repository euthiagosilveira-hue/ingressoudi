import type { H3Event } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

import { avaliarCobrancaPix, type PixParaConferir } from '../services/payments/conferir-pix-regras'
import { MercadoPagoPaymentsProvider } from '../services/payments/mercado-pago/mercado-pago-payments'
import { obterAccessTokenOrganizacao } from '../services/payments/mercado-pago/mercado-pago-conexao'
import { alertarErroPagamento } from './alerta-pagamento'

export type ResultadoConferenciaPix = 'CONFIRMADO' | 'NAO_PAGO' | 'IGNORADO' | 'ERRO'

/**
 * Consulta o Pix no Mercado Pago e, se estiver pago, confirma o pedido
 * (private.confirmar_pagamento aceita reserva vencida e emite os ingressos).
 * Rede de seguranca para quando o webhook nao chega. Nunca lanca erro.
 */
export async function conferirPix(
  event: H3Event,
  pix: PixParaConferir,
  tokens: Map<string, string | null> = new Map()
): Promise<ResultadoConferenciaPix> {
  try {
    let accessToken = tokens.get(pix.organizacaoId)
    if (accessToken === undefined) {
      accessToken = await obterAccessTokenOrganizacao(event, pix.organizacaoId).catch(() => null)
      tokens.set(pix.organizacaoId, accessToken)
    }
    if (!accessToken) return 'IGNORADO'

    const charge = await new MercadoPagoPaymentsProvider(accessToken).getCharge(pix.cobrancaId)
    const avaliacao = avaliarCobrancaPix(charge, pix)
    if (avaliacao === 'NAO_PAGO') return 'NAO_PAGO'
    if (avaliacao === 'OUTRA_REFERENCIA') return 'IGNORADO'
    if (avaliacao === 'VALOR_DIVERGENTE') {
      await alertarErroPagamento(event, {
        tipo: 'VALOR_DIVERGENTE',
        organizacaoId: pix.organizacaoId,
        mensagem: 'Pix aprovado com valor diferente do pedido; não foi confirmado.',
        detalhe: { valorMp: charge.amount ?? null, valorPedido: Number(pix.valor) },
        referencia: pix.pagamentoId
      })
      return 'IGNORADO'
    }

    const client = serverSupabaseServiceRole(event)
    const { error } = await client.rpc('confirmar_pagamento', {
      p_pagamento_id: pix.pagamentoId,
      p_transaction_id: charge.transactionId,
      p_referencia_externa: charge.externalReference || pix.pagamentoId
    })
    if (error) {
      await alertarErroPagamento(event, {
        tipo: 'CONFIRMACAO',
        organizacaoId: pix.organizacaoId,
        mensagem: 'Pix aprovado no Mercado Pago, mas a confirmação no sistema falhou na conferência.',
        detalhe: { erro: error.message },
        referencia: pix.pagamentoId
      })
      return 'ERRO'
    }
    return 'CONFIRMADO'
  } catch (erro) {
    console.error('[conferir-pix] falha', {
      pagamentoId: pix.pagamentoId,
      erro: erro instanceof Error ? erro.message : 'erro'
    })
    return 'ERRO'
  }
}
