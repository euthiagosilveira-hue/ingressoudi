import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'

import { listarPedidosAdmin } from '~/services/admin/pedidos'
import { listarEventosAdmin } from '~/services/admin/eventos'
import type { OrderFiltersState, OrderListItem, OrderSort } from '~/types/pedido'
import type { SelectOption } from '~/types/ui'
import { paginar, totalPaginas } from '~/utils/paginacao'
import { mapearPedidoAdminParaListItem, ordenarPedidos, resumoPedidos } from '~/utils/pedidos'

const DEBOUNCE_FILTROS_MS = 350

/**
 * Listagem administrativa de pedidos: filtros server-side (RPC), ordenacao,
 * paginacao e resumo reaproveitando os utilitarios existentes. A UI permanece.
 */
export function useAdminOrders(porPagina = 10) {
  const route = useRoute()

  const eventoQuery = typeof route.query.evento === 'string' ? route.query.evento : ''

  const filtros = reactive<OrderFiltersState>({
    busca: '',
    eventoId: eventoQuery || 'TODOS',
    status: 'TODOS',
    tipoPreco: 'TODOS'
  })

  const ordenacao = ref<OrderSort>('RECENTES')
  const pagina = ref(1)

  const pedidos = ref<OrderListItem[]>([])
  const eventos = ref<{ id: string; nome: string }[]>([])

  let debounce: ReturnType<typeof setTimeout> | null = null

  const pedidosOrdenados = computed(() => ordenarPedidos(pedidos.value, ordenacao.value))
  const total = computed(() => pedidosOrdenados.value.length)
  const numeroPaginas = computed(() => totalPaginas(total.value, porPagina))
  const pedidosPaginados = computed(() =>
    paginar(pedidosOrdenados.value, pagina.value, porPagina)
  )
  const resumo = computed(() => resumoPedidos(pedidosOrdenados.value))

  const temFiltros = computed(
    () =>
      filtros.busca.trim() !== '' ||
      filtros.eventoId !== 'TODOS' ||
      filtros.status !== 'TODOS' ||
      filtros.tipoPreco !== 'TODOS'
  )

  const eventoOptions = computed<SelectOption[]>(() => [
    { value: 'TODOS', label: 'Todos os eventos' },
    ...eventos.value.map((evento) => ({ value: evento.id, label: evento.nome }))
  ])

  async function carregar() {
    try {
      const rows = await listarPedidosAdmin({
        busca: filtros.busca,
        eventoId: filtros.eventoId === 'TODOS' ? null : filtros.eventoId,
        status: filtros.status === 'TODOS' ? null : filtros.status,
        tipoPreco: filtros.tipoPreco === 'TODOS' ? null : filtros.tipoPreco
      })
      pedidos.value = rows.map(mapearPedidoAdminParaListItem)
    } catch {
      pedidos.value = []
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
    filtros.tipoPreco = 'TODOS'
  }

  function irPara(valor: number) {
    pagina.value = Math.min(Math.max(valor, 1), numeroPaginas.value)
  }

  return {
    filtros,
    ordenacao,
    pagina,
    pedidosPaginados,
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
