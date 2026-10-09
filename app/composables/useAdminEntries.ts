import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'

import { listarEntradasAdmin } from '~/services/admin/entradas'
import { listarEventosAdmin } from '~/services/admin/eventos'
import type { EntryFiltersState, EntryListItem, EntrySort } from '~/types/entrada'
import type { SelectOption } from '~/types/ui'
import { mapearEntradaAdminParaListItem, ordenarEntradas, resumoEntradas } from '~/utils/entradas'
import { paginar, totalPaginas } from '~/utils/paginacao'

const DEBOUNCE_FILTROS_MS = 350

function inicioDoPeriodo(periodo: EntryFiltersState['periodo']): string | null {
  if (periodo === 'TODAS') return null
  const agora = new Date()
  if (periodo === 'HOJE') {
    const inicio = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate())
    return inicio.toISOString()
  }
  const dias = periodo === 'SETE_DIAS' ? 7 : 30
  return new Date(agora.getTime() - dias * 86_400_000).toISOString()
}

/**
 * Listagem administrativa de entradas: filtros server-side (RPC), ordenacao,
 * paginacao e resumo reaproveitando os utilitarios existentes. A UI permanece.
 * Somente leitura nesta etapa (anular nao e implementado).
 */
export function useAdminEntries(porPagina = 10) {
  const route = useRoute()
  const eventoQuery = typeof route.query.evento === 'string' ? route.query.evento : ''

  const filtros = reactive<EntryFiltersState>({
    busca: '',
    eventoId: eventoQuery || 'TODOS',
    metodo: 'TODOS',
    situacao: 'TODOS',
    periodo: 'TODAS'
  })

  const ordenacao = ref<EntrySort>('RECENTES')
  const pagina = ref(1)

  const itens = ref<EntryListItem[]>([])
  const eventos = ref<{ id: string; nome: string }[]>([])

  let debounce: ReturnType<typeof setTimeout> | null = null

  const itensOrdenados = computed(() => ordenarEntradas(itens.value, ordenacao.value))
  const total = computed(() => itensOrdenados.value.length)
  const numeroPaginas = computed(() => totalPaginas(total.value, porPagina))
  const entradasPaginadas = computed(() =>
    paginar(itensOrdenados.value, pagina.value, porPagina)
  )
  const resumo = computed(() => resumoEntradas(itensOrdenados.value))

  const temFiltros = computed(
    () =>
      filtros.busca.trim() !== '' ||
      filtros.eventoId !== 'TODOS' ||
      filtros.metodo !== 'TODOS' ||
      filtros.situacao !== 'TODOS' ||
      filtros.periodo !== 'TODAS'
  )

  const eventoOptions = computed<SelectOption[]>(() => [
    { value: 'TODOS', label: 'Todos os eventos' },
    ...eventos.value.map((evento) => ({ value: evento.id, label: evento.nome }))
  ])

  async function carregar() {
    try {
      const rows = await listarEntradasAdmin({
        busca: filtros.busca,
        eventoId: filtros.eventoId === 'TODOS' ? null : filtros.eventoId,
        metodo: filtros.metodo === 'TODOS' ? null : filtros.metodo,
        situacao: filtros.situacao === 'TODOS' ? null : filtros.situacao,
        de: inicioDoPeriodo(filtros.periodo)
      })
      itens.value = rows.map(mapearEntradaAdminParaListItem)
    } catch {
      itens.value = []
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
    filtros.metodo = 'TODOS'
    filtros.situacao = 'TODOS'
    filtros.periodo = 'TODAS'
  }

  function irPara(valor: number) {
    pagina.value = Math.min(Math.max(valor, 1), numeroPaginas.value)
  }

  return {
    itens,
    filtros,
    ordenacao,
    pagina,
    entradasPaginadas,
    total,
    numeroPaginas,
    resumo,
    temFiltros,
    limparFiltros,
    irPara,
    eventoOptions,
    carregar,
    refresh: carregar
  }
}
