<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import { formatDataHora } from '~/utils/format'
import type { SelectOption } from '~/types/ui'
import type { EventListItem } from '~/types/evento'

const props = defineProps<{
  modelValue: string
  eventos: EventListItem[]
  evento: EventListItem | null
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const opcoes = computed<SelectOption[]>(() => [
  { value: '', label: 'Selecione o evento' },
  ...props.eventos.map((evento) => ({ value: evento.id, label: evento.nome }))
])

const selecionado = computed({
  get: () => props.modelValue,
  set: (valor: string) => emit('update:modelValue', valor)
})
</script>

<template>
  <BaseCard class="space-y-4">
    <BaseSelect v-model="selecionado" :options="opcoes" label="Evento em operação" />

    <div
      v-if="props.evento"
      class="flex min-w-0 flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-zinc-800 bg-zinc-950/60 p-3 text-sm text-zinc-400"
    >
      <span class="min-w-0 break-words font-semibold text-white">{{ props.evento.nome }}</span>
      <EventStatusBadge :status="props.evento.status" />
      <span>{{ formatDataHora(props.evento.inicioEm) }}</span>
      <span class="min-w-0 break-words">{{ props.evento.local }}</span>
    </div>
  </BaseCard>
</template>
