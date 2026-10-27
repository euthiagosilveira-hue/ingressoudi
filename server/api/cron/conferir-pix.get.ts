import { serverSupabaseServiceRole } from '#supabase/server'

import { DIAS_CONFERENCIA_DIARIA } from '../../services/payments/conferir-pix-regras'
import { alertarErroPagamento } from '../../utils/alerta-pagamento'
import { conferirPix } from '../../utils/conferir-pix'

const MAXIMO_POR_EXECUCAO = 300
const EM_PARALELO = 5

/**
 * Conferencia diaria (Vercel Cron, ver vercel.json): todo Pix dos ultimos dias
 * que ainda nao esta APROVADO e consultado no Mercado Pago. O que estiver pago
 * e confirmado, mesmo com a reserva ja expirada. Exige CRON_SECRET.
 */
export default defineEventHandler(async (event) => {
  const segredo = String(process.env.CRON_SECRET ?? '')
  if (!segredo || getHeader(event, 'authorization') !== `Bearer ${segredo}`) {
    setResponseStatus(event, 401)
    return { error: 'NAO_AUTORIZADO' }
  }

  const client = serverSupabaseServiceRole(event)
  const desde = new Date(Date.now() - DIAS_CONFERENCIA_DIARIA * 86_400_000).toISOString()
  const { data, error } = await client
    .from('pagamentos')
    .select('id,organizacao_id,cobranca_id,valor')
    .eq('provedor', 'MERCADO_PAGO')
    .in('status', ['PENDENTE', 'EXPIRADO'])
    .not('cobranca_id', 'is', null)
    .gte('criado_em', desde)
    .order('criado_em', { ascending: false })
    .limit(MAXIMO_POR_EXECUCAO)

  if (error) {
    setResponseStatus(event, 500)
    return { error: 'ERRO_INESPERADO' }
  }

  const tokens = new Map<string, string | null>()
  const contagem = { conferidos: 0, confirmados: 0, erros: 0 }
  const confirmadosPorCasa = new Map<string, number>()

  const linhas = data ?? []
  // Poucas consultas em paralelo para caber no tempo da funcao.
  for (let i = 0; i < linhas.length; i += EM_PARALELO) {
    await Promise.all(
      linhas.slice(i, i + EM_PARALELO).map(async (row) => {
        const organizacaoId = String(row.organizacao_id)
        const resultado = await conferirPix(
          event,
          { pagamentoId: String(row.id), organizacaoId, cobrancaId: String(row.cobranca_id), valor: row.valor },
          tokens
        )
        contagem.conferidos += 1
        if (resultado === 'CONFIRMADO') {
          contagem.confirmados += 1
          confirmadosPorCasa.set(organizacaoId, (confirmadosPorCasa.get(organizacaoId) ?? 0) + 1)
        } else if (resultado === 'ERRO') {
          contagem.erros += 1
        }
      })
    )
  }

  // Pix pago confirmado so aqui significa que o webhook falhou: avisa.
  for (const [organizacaoId, total] of confirmadosPorCasa) {
    await alertarErroPagamento(event, {
      tipo: 'WEBHOOK',
      organizacaoId,
      mensagem: `${total} Pix pago(s) só foram confirmados na conferência diária; o aviso do Mercado Pago não chegou.`
    })
  }

  return contagem
})
