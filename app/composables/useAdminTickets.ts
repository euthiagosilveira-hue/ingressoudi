import { computed, onMounted, onUnmounted, reactive, ref, watch } from 'vue'

import { listarIngressosAdmin } from '~/services/admin/ingressos'
import { listarEventosAdmin } from '~/services/admin/eventos'
import type { TicketFiltersState, TicketListItem, TicketSort } from '~/types/ingresso'
import type { SelectOption } from '~/types/ui'
import { mapearIngressoAdminParaListItem, ordenarIngressos, resumoIngressos } from '~/utils/ingressos'
import { paginar, totalPaginas } from '~/utils/paginacao'

const DEBOUNCE_FILTROS_MS = 350

/**
 * Listagem administrativa de ingressos: filtros server-side (RPC), ordenacao,
 * paginacao e resumo reaproveitando os utilitarios existentes. A UI permanece.
 */
export function useAdminTickets(porPagina = 10) {
  const route = useRoute()

  const eventoQuery = typeof route.query.evento === 'string' ? route.query.evento : ''
  const pedidoQuery = typeof route.query.pedido === 'string' ? route.query.pedido : ''

  const filtros = reactive<TicketFiltersState>({
    busca: '',
    eventoId: eventoQuery || 'TODOS',
    status: 'TODOS'
  })

  // Filtro por pedido via query param (?pedido=<uuid>) — sem controle visual novo.
  const pedidoId = ref<string | null>(pedidoQuery || null)

  const ordenacao = ref<TicketSort>('RECENTES')
  const pagina = ref(1)

  const ingressos = ref<TicketListItem[]>([])
  const eventos = ref<{ id: string; nome: string }[]>([])

  let debounce: ReturnType<typeof setTimeout> | null = null

  const ingressosOrdenados = computed(() => ordenarIngressos(ingressos.value, ordenacao.value))
  const total = computed(() => ingressosOrdenados.value.length)
  const numeroPaginas = computed(() => totalPaginas(total.value, porPagina))
  const ingressosPaginados = computed(() =>
    paginar(ingressosOrdenados.value, pagina.value, porPagina)
  )
  const resumo = computed(() => resumoIngressos(ingressosOrdenados.value))

  const temFiltros = computed(
    () =>
      filtros.busca.trim() !== '' ||
      filtros.eventoId !== 'TODOS' ||
      filtros.status !== 'TODOS' ||
      pedidoId.value !== null
  )

  const eventoOptions = computed<SelectOption[]>(() => [
    { value: 'TODOS', label: 'Todos os eventos' },
    ...eventos.value.map((evento) => ({ value: evento.id, label: evento.nome }))
  ])

  async function carregar() {
    try {
      const rows = await listarIngressosAdmin({
        busca: filtros.busca,
        eventoId: filtros.eventoId === 'TODOS' ? null : filtros.eventoId,
        pedidoId: pedidoId.value,
        status: filtros.status === 'TODOS' ? null : filtros.status
      })
      ingressos.value = rows.map(mapearIngressoAdminParaListItem)
    } catch {
      ingressos.value = []
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

  watch(pedidoId, () => {
    pagina.value = 1
    void carregar()
  })

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
    pedidoId.value = null
  }

  function irPara(valor: number) {
    pagina.value = Math.min(Math.max(valor, 1), numeroPaginas.value)
  }

  return {
    filtros,
    ordenacao,
    pagina,
    ingressosPaginados,
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
