import { computed, ref } from 'vue'

import type { EventListItem, EventStatus } from '~/types/evento'
import type { GateMode } from '~/types/portaria'

const STATUS_OPERACIONAIS: EventStatus[] = ['AGENDADO', 'EM_ANDAMENTO']

/**
 * Estado operacional da portaria: apenas selecao de evento e modo de leitura.
 * Os fluxos (QR e busca por nome) sao reais e ficam em seus composables.
 */
export function useGate(todosEventos: EventListItem[]) {
  const eventosOperacionais = computed(() =>
    todosEventos.filter((evento) => STATUS_OPERACIONAIS.includes(evento.status))
  )

  const eventoId = ref('')
  const modo = ref<GateMode>('QR')

  const eventoAtual = computed(
    () => eventosOperacionais.value.find((evento) => evento.id === eventoId.value) ?? null
  )

  function selecionarEvento(id: string) {
    eventoId.value = id
  }

  function definirModo(novoModo: GateMode) {
    modo.value = novoModo
  }

  return {
    eventosOperacionais,
    eventoId,
    eventoAtual,
    modo,
    selecionarEvento,
    definirModo
  }
}
