import { computed, onMounted, ref } from 'vue'

import { obterDashboardAdmin, obterPainelEventoAdmin } from '~/services/admin/dashboard'
import type { AdminDashboardData, AdminPainelEventoExtras } from '~/types/dashboard'
import { mapearDashboard } from '~/utils/dashboard'

const VAZIO: AdminDashboardData = {
  metricas: { vendidos: 0, utilizados: 0, naoEntraram: 0, faturamento: 0, ticketMedio: 0 },
  evento: null,
  entradasPorHora: [],
  pagamentosPorStatus: [],
  pedidosRecentes: [],
  entradasRecentes: []
}

/**
 * Dashboard administrativo: dados reais via RPC + view-models prontos.
 * Com eventoId, mostra so aquele evento (com dados extras do evento).
 */
export function useAdminDashboard(eventoId?: string) {
  const data = ref<AdminDashboardData>(VAZIO)
  const extras = ref<AdminPainelEventoExtras | null>(null)
  const carregando = ref(true)
  const erro = ref('')

  const viewModel = computed(() => mapearDashboard(data.value))

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      if (eventoId) {
        const painel = await obterPainelEventoAdmin(eventoId)
        data.value = painel
        extras.value = painel.extras
      } else {
        data.value = await obterDashboardAdmin()
      }
    } catch (e) {
      erro.value = eventoId && e instanceof Error ? e.message : 'Não foi possível carregar o dashboard.'
      data.value = VAZIO
      extras.value = null
    } finally {
      carregando.value = false
    }
  }

  onMounted(() => {
    void carregar()
  })

  return {
    data,
    extras,
    viewModel,
    carregando,
    erro,
    carregar,
    refresh: carregar
  }
}
