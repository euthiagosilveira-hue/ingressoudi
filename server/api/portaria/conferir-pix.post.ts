import { serverSupabaseClient } from '#supabase/server'

import { ehUuid } from '../../services/payments/payment-service'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'
import { conferirPix } from '../../utils/conferir-pix'
import { limitar } from '../../utils/rate-limit'

/**
 * Portaria leu um ingresso EXPIRADO ou ainda nao pago: confere o Pix no
 * Mercado Pago na hora. Se estiver pago, confirma o pedido e o aparelho tenta
 * registrar a entrada de novo. A permissao (operador da portaria da casa) e
 * checada no banco por localizar_pix_portaria, com a sessao do operador.
 */
export default defineEventHandler(async (event) => {
  if (!limitar(event, 30)) {
    setResponseStatus(event, 429)
    return { confirmado: false }
  }

  const body = await readBody<{ eventoId?: string; ingressoId?: string }>(event).catch(
    () => ({}) as { eventoId?: string; ingressoId?: string }
  )
  const eventoId = String(body?.eventoId ?? '')
  const ingressoId = String(body?.ingressoId ?? '')
  if (!ehUuid(eventoId) || !ehUuid(ingressoId)) {
    setResponseStatus(event, 400)
    return { confirmado: false }
  }

  const operador = await serverSupabaseClient(event)
  const { data, error } = await operador.rpc('localizar_pix_portaria', {
    p_evento_id: eventoId,
    p_ingresso_id: ingressoId
  })
  if (error) {
    setResponseStatus(event, error.code === '42501' ? 403 : 500)
    return { confirmado: false }
  }

  const pix = data as { pagamento_id: string; organizacao_id: string; cobranca_id: string; valor: number | string } | null
  if (!pix) return { confirmado: false }

  const resultado = await conferirPix(event, {
    pagamentoId: pix.pagamento_id,
    organizacaoId: pix.organizacao_id,
    cobrancaId: pix.cobranca_id,
    valor: pix.valor
  })

  if (resultado === 'CONFIRMADO') {
    // O webhook deveria ter confirmado antes: avisa o super admin.
    await alertarErroPagamento(event, {
      tipo: 'WEBHOOK',
      organizacaoId: pix.organizacao_id,
      mensagem: 'Pix pago só foi confirmado na portaria; o aviso do Mercado Pago não chegou a tempo.',
      referencia: pix.pagamento_id
    })
  }

  return { confirmado: resultado === 'CONFIRMADO' }
})
