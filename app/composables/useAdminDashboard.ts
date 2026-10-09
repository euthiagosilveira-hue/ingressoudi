import { computed, onMounted, ref } from 'vue'

import { obterDashboardAdmin } from '~/services/admin/dashboard'
import type { AdminDashboardData } from '~/types/dashboard'
import { mapearDashboard } from '~/utils/dashboard'

const VAZIO: AdminDashboardData = {
  metricas: { vendidos: 0, utilizados: 0, naoEntraram: 0, faturamento: 0, ticketMedio: 0 },
  evento: null,
  entradasPorHora: [],
  pagamentosPorStatus: [],
  pedidosRecentes: [],
  entradasRecentes: []
}

/** Dashboard administrativo: dados reais via RPC + view-models prontos. */
export function useAdminDashboard() {
  const data = ref<AdminDashboardData>(VAZIO)
  const carregando = ref(true)
  const erro = ref('')

  const viewModel = computed(() => mapearDashboard(data.value))

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      data.value = await obterDashboardAdmin()
    } catch {
      erro.value = 'Não foi possível carregar o dashboard.'
      data.value = VAZIO
    } finally {
      carregando.value = false
    }
  }

  onMounted(() => {
    void carregar()
  })

  return {
    data,
    viewModel,
    carregando,
    erro,
    carregar,
    refresh: carregar
  }
}
