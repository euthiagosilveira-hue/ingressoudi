import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'

import { obterFinanceiroAdmin } from '~/services/admin/financeiro'
import { listarEventosAdmin } from '~/services/admin/eventos'
import type {
  FinancialFiltersState,
  FinancialSummaryData,
  FinancialSort,
  PaymentListItem
} from '~/types/pagamento'
import type { SelectOption } from '~/types/ui'
import { ordenarPagamentos } from '~/utils/financeiro'
import { paginar, totalPaginas } from '~/utils/paginacao'

const DEBOUNCE_FILTROS_MS = 350

function inicioDoPeriodo(periodo: FinancialFiltersState['periodo']): string | null {
  if (periodo === 'TODAS') return null
  const agora = new Date()
  if (periodo === 'HOJE') {
    return new Date(agora.getFullYear(), agora.getMonth(), agora.getDate()).toISOString()
  }
  const dias = periodo === 'SETE_DIAS' ? 7 : 30
  return new Date(agora.getTime() - dias * 86_400_000).toISOString()
}

const RESUMO_VAZIO: FinancialSummaryData = {
  total: 0,
  aprovados: 0,
  valorAprovado: 0,
  pendente: 0,
  reembolsado: 0,
  liquido: 0
}

/**
 * Financeiro administrativo: resumo e movimentacoes vindos de RPC real,
 * com filtros server-side. Ordenacao/paginacao seguem client-side (dataset
 * administrativo razoavel). A UI permanece.
 */
export function useAdminFinance(porPagina = 10) {
  const route = useRoute()
  const eventoQuery = typeof route.query.evento === 'string' ? route.query.evento : ''

  const filtros = reactive<FinancialFiltersState>({
    busca: '',
    eventoId: eventoQuery || 'TODOS',
    status: 'TODOS',
    periodo: 'TODAS'
  })

  const ordenacao = ref<FinancialSort>('RECENTES')
  const pagina = ref(1)

  const resumo = ref<FinancialSummaryData>({ ...RESUMO_VAZIO })
  const movimentacoes = ref<PaymentListItem[]>([])
  const eventos = ref<{ id: string; nome: string }[]>([])

  let debounce: ReturnType<typeof setTimeout> | null = null

  const movimentacoesOrdenadas = computed(() =>
    ordenarPagamentos(movimentacoes.value, ordenacao.value)
  )
  const total = computed(() => movimentacoesOrdenadas.value.length)
  const numeroPaginas = computed(() => totalPaginas(total.value, porPagina))
  const pagamentosPaginados = computed(() =>
    paginar(movimentacoesOrdenadas.value, pagina.value, porPagina)
  )

  const temFiltros = computed(
    () =>
      filtros.busca.trim() !== '' ||
      filtros.eventoId !== 'TODOS' ||
      filtros.status !== 'TODOS' ||
      filtros.periodo !== 'TODAS'
  )

  const eventoOptions = computed<SelectOption[]>(() => [
    { value: 'TODOS', label: 'Todos os eventos' },
    ...eventos.value.map((evento) => ({ value: evento.id, label: evento.nome }))
  ])

  async function carregar() {
    try {
      const resultado = await obterFinanceiroAdmin({
        busca: filtros.busca,
        eventoId: filtros.eventoId === 'TODOS' ? null : filtros.eventoId,
        status: filtros.status === 'TODOS' ? null : filtros.status,
        de: inicioDoPeriodo(filtros.periodo)
      })
      resumo.value = resultado.resumo
      movimentacoes.value = resultado.movimentacoes
    } catch {
      resumo.value = { ...RESUMO_VAZIO }
      movimentacoes.value = []
    }
  }

  async function carregarEventos() {
    try {
      const lista = await listarEventosAdmin()
      eventos.value = lista.map((evento) => ({ id: evento.eventoId, nome: evento.nome }))
    } catch {
      eventos.value = []
    }
  }

  watch(
    filtros,
    () => {
      pagina.value = 1
      if (debounce) clearTimeout(debounce)
      debounce = setTimeout(() => {
        void carregar()
      }, DEBOUNCE_FILTROS_MS)
    },
    { deep: true }
  )

  watch(ordenacao, () => {
    pagina.value = 1
  })

  watch(numeroPaginas, (maximo) => {
    if (pagina.value > maximo) pagina.value = maximo
  })

  onMounted(() => {
    void carregar()
    void carregarEventos()
  })

  onUnmounted(() => {
    if (debounce) clearTimeout(debounce)
  })

  function limparFiltros() {
    filtros.busca = ''
    filtros.eventoId = 'TODOS'
    filtros.status = 'TODOS'
    filtros.periodo = 'TODAS'
  }

  function irPara(valor: number) {
    pagina.value = Math.min(Math.max(valor, 1), numeroPaginas.value)
  }

  return {
    filtros,
    ordenacao,
    pagina,
    resumo,
    movimentacoes,
    pagamentos: movimentacoes,
    pagamentosPaginados,
    total,
    numeroPaginas,
    temFiltros,
    limparFiltros,
    irPara,
    eventoOptions,
    carregar,
    refresh: carregar
  }
}
