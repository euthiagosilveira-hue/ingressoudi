import type { AdminDashboardData, AdminPainelEventoData } from '~/types/dashboard'

/** Dashboard administrativo real (RPC segura, ADMINISTRADOR). */
export async function obterDashboardAdmin(): Promise<AdminDashboardData> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_dashboard_admin')
  if (error) {
    throw new Error('Não foi possível carregar o dashboard.')
  }
  return normalizarDashboard(data)
}

function normalizarDashboard(data: unknown): AdminDashboardData {
  const d = (data ?? {}) as Partial<AdminDashboardData>
  return {
    metricas: d.metricas ?? {
      vendidos: 0,
      utilizados: 0,
      naoEntraram: 0,
      faturamento: 0,
      ticketMedio: 0
    },
    evento: d.evento ?? null,
    entradasPorHora: d.entradasPorHora ?? [],
    pagamentosPorStatus: d.pagamentosPorStatus ?? [],
    pedidosRecentes: d.pedidosRecentes ?? [],
    entradasRecentes: d.entradasRecentes ?? []
  }
}

/** Dashboard de um evento da organizacao ativa (RPC segura, ADMINISTRADOR). */
export async function obterPainelEventoAdmin(eventoId: string): Promise<AdminPainelEventoData> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_painel_evento_admin', { p_evento_id: eventoId })
  if (error) {
    throw new Error(
      (error.message ?? '').toLowerCase().includes('nao encontrado')
        ? 'Evento não encontrado.'
        : 'Não foi possível carregar o dashboard do evento.'
    )
  }
  const extras = ((data ?? {}) as { extras?: AdminPainelEventoData['extras'] }).extras ?? null
  return { ...normalizarDashboard(data), extras }
}
