import type { AdminDashboardData } from '~/types/dashboard'

/** Dashboard administrativo real (RPC segura, ADMINISTRADOR). */
export async function obterDashboardAdmin(): Promise<AdminDashboardData> {
  const client = useSupabaseClient()
  const { data, error } = await client.rpc('obter_dashboard_admin')
  if (error) {
    throw new Error('Não foi possível carregar o dashboard.')
  }
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
