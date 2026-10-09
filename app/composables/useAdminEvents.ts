import { computed, onMounted, onUnmounted, ref, watch } from 'vue'

import { listarEventosAdmin } from '~/services/admin/eventos'
import type { AdminEventListItem, EventFiltersState } from '~/types/evento'
import { mapearEventoAdminParaListItem } from '~/utils/eventos'

const DEBOUNCE_BUSCA_MS = 350

/** Listagem administrativa de eventos: filtros server-side, loading e refresh. */
export function useAdminEvents() {
  const filtros = ref<EventFiltersState>({
    busca: '',
    status: 'TODOS',
    publicacao: 'TODOS'
  })

  const eventos = ref<AdminEventListItem[]>([])
  const carregando = ref(true)
  const erro = ref('')

  let debounce: ReturnType<typeof setTimeout> | null = null

  const eventosLista = computed(() => eventos.value.map(mapearEventoAdminParaListItem))

  const filtrosAtivos = computed(
    () =>
      filtros.value.busca.trim() !== '' ||
      filtros.value.status !== 'TODOS' ||
      filtros.value.publicacao !== 'TODOS'
  )

  async function carregar() {
    carregando.value = true
    erro.value = ''
    try {
      eventos.value = await listarEventosAdmin({
        busca: filtros.value.busca,
        status: filtros.value.status === 'TODOS' ? null : filtros.value.status,
        publicacao: filtros.value.publicacao === 'TODOS' ? null : filtros.value.publicacao
      })
    } catch {
      erro.value = 'Não foi possível carregar os eventos.'
      eventos.value = []
    } finally {
      carregando.value = false
    }
  }

  watch(
    filtros,
    () => {
      if (debounce) clearTimeout(debounce)
      debounce = setTimeout(() => {
        void carregar()
      }, DEBOUNCE_BUSCA_MS)
    },
    { deep: true }
  )

  onMounted(() => {
    void carregar()
  })

  onUnmounted(() => {
    if (debounce) clearTimeout(debounce)
  })

  return {
    filtros,
    eventos,
    eventosLista,
    carregando,
    erro,
    filtrosAtivos,
    carregar,
    refresh: carregar
  }
}
