import { serverSupabaseClient } from '#supabase/server'

import { ehUuid } from '../../services/payments/payment-service'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'
import { conferirPix } from '../../utils/conferir-pix'
import { limitar } from '../../utils/rate-limit'

const EM_PARALELO = 5

/**
 * Operador abriu o evento na portaria: confere de uma vez no Mercado Pago os
 * Pix do evento ainda nao aprovados e confirma os que estiverem pagos. O banco
 * (iniciar_conferencia_pix_evento) checa a permissao e libera no maximo uma
 * conferencia a cada 30 minutos por evento.
 */
export default defineEventHandler(async (event) => {
  if (!limitar(event, 10)) {
    setResponseStatus(event, 429)
    return { conferidos: 0, confirmados: 0 }
  }

  const body = await readBody<{ eventoId?: string }>(event).catch(() => ({}) as { eventoId?: string })
  const eventoId = String(body?.eventoId ?? '')
  if (!ehUuid(eventoId)) {
    setResponseStatus(event, 400)
    return { conferidos: 0, confirmados: 0 }
  }

  const operador = await serverSupabaseClient(event)
  const { data, error } = await operador.rpc('iniciar_conferencia_pix_evento', { p_evento_id: eventoId })
  if (error) {
    setResponseStatus(event, error.code === '42501' ? 403 : 500)
    return { conferidos: 0, confirmados: 0 }
  }

  const lista = (data ?? []) as Array<{ pagamento_id: string; organizacao_id: string; cobranca_id: string; valor: number | string }>
  const tokens = new Map<string, string | null>()
  let confirmados = 0
  let organizacaoId = ''

  for (let i = 0; i < lista.length; i += EM_PARALELO) {
    await Promise.all(
      lista.slice(i, i + EM_PARALELO).map(async (pix) => {
        organizacaoId = pix.organizacao_id
        const resultado = await conferirPix(
          event,
          { pagamentoId: pix.pagamento_id, organizacaoId: pix.organizacao_id, cobrancaId: pix.cobranca_id, valor: pix.valor },
          tokens
        )
        if (resultado === 'CONFIRMADO') confirmados += 1
      })
    )
  }

  if (confirmados > 0) {
    // O webhook deveria ter confirmado antes: avisa o super admin.
    await alertarErroPagamento(event, {
      tipo: 'WEBHOOK',
      organizacaoId,
      mensagem: `${confirmados} Pix pago(s) só foram confirmados na abertura da portaria; o aviso do Mercado Pago não chegou.`,
      referencia: eventoId
    })
  }

  return { conferidos: lista.length, confirmados }
})
