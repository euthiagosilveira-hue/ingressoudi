import type { AdminDashboardData, AdminPainelEventoData, AdminPainelSetor } from '~/types/dashboard'

interface SetorPainelRow {
  setor_id: string
  nome: string
  vendidos?: number | null
  utilizados?: number | null
  receita?: number | string | null
  capacidade?: number | null
  lote_atual?: { nome: string; preco: number | string; disponiveis: number } | null
}

export function mapearSetorPainel(row: SetorPainelRow): AdminPainelSetor {
  return {
    setorId: row.setor_id,
    nome: row.nome,
    vendidos: Number(row.vendidos ?? 0),
    utilizados: Number(row.utilizados ?? 0),
    receita: Number(row.receita ?? 0),
    capacidade: Number(row.capacidade ?? 0),
    loteAtual: row.lote_atual
      ? { nome: row.lote_atual.nome, preco: Number(row.lote_atual.preco), disponiveis: Number(row.lote_atual.disponiveis) }
      : null
  }
}

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
  const bruto = (data ?? {}) as { extras?: AdminPainelEventoData['extras']; setores?: SetorPainelRow[] | null }
  const extras = bruto.extras ? { ...bruto.extras, setores: (bruto.setores ?? []).map(mapearSetorPainel) } : null
  return { ...normalizarDashboard(data), extras }
}
