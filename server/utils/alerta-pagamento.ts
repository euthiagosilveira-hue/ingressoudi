import type { H3Event } from 'h3'

import { serverSupabaseServiceRole } from '#supabase/server'

import { enviarPush, type AssinaturaPush } from './push'
import { avisoErroPagamento, type TipoErroPagamento } from './push-mensagens'

export interface ErroPagamento {
  tipo: TipoErroPagamento
  organizacaoId?: string | null
  mensagem: string
  /** Somente dados tecnicos seguros (nunca tokens, headers ou corpo bruto). */
  detalhe?: Record<string, unknown> | null
  /** Pedido, pagamento ou id do Mercado Pago relacionado. */
  referencia?: string | null
}

/**
 * Grava o erro de pagamento e avisa os super admins por push (o banco limita a
 * um aviso a cada 15 minutos por tipo e casa). Nunca lanca erro: uma falha
 * aqui nao pode atrapalhar o fluxo de pagamento.
 */
export async function alertarErroPagamento(event: H3Event, erro: ErroPagamento): Promise<void> {
  try {
    const client = serverSupabaseServiceRole(event)
    const { data, error } = await client.rpc('registrar_erro_pagamento', {
      p_tipo: erro.tipo,
      p_organizacao_id: erro.organizacaoId || null,
      p_mensagem: erro.mensagem,
      p_detalhe: erro.detalhe ?? null,
      p_referencia: erro.referencia ?? null
    })
    if (error) {
      console.error('[alerta-pagamento] falha ao registrar', { tipo: erro.tipo, mensagem: error.message })
      return
    }

    const reserva = (data ?? {}) as { enviar?: boolean; organizacao_nome?: string | null; assinaturas?: AssinaturaPush[] }
    if (!reserva.enviar || !reserva.assinaturas?.length) return

    const { expirados } = await enviarPush(
      reserva.assinaturas,
      avisoErroPagamento(erro.tipo, reserva.organizacao_nome ?? null, erro.mensagem)
    )
    if (expirados.length) {
      await client.from('push_assinaturas').delete().in('endpoint', expirados)
    }
  } catch (e) {
    console.error('[alerta-pagamento] falha inesperada', {
      tipo: erro.tipo,
      mensagem: e instanceof Error ? e.message : 'erro'
    })
  }
}
