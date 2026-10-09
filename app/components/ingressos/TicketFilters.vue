<script setup lang="ts">
import { computed } from 'vue'
import { MagnifyingGlassIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import type { SelectOption } from '~/types/ui'
import type { TicketFiltersState, TicketStatusFilter } from '~/types/ingresso'

const props = defineProps<{
  modelValue: TicketFiltersState
  eventos: SelectOption[]
}>()

const emit = defineEmits<{
  'update:modelValue': [value: TicketFiltersState]
}>()

const busca = computed({
  get: () => props.modelValue.busca,
  set: (valor: string) => emit('update:modelValue', { ...props.modelValue, busca: valor })
})

const evento = computed({
  get: () => props.modelValue.eventoId,
  set: (valor: string) => emit('update:modelValue', { ...props.modelValue, eventoId: valor })
})

const status = computed({
  get: () => props.modelValue.status,
  set: (valor: string) =>
    emit('update:modelValue', { ...props.modelValue, status: valor as TicketStatusFilter })
})

const statusOptions: SelectOption[] = [
  { value: 'TODOS', label: 'Todos os status' },
  { value: 'VALIDO', label: 'Válido' },
  { value: 'UTILIZADO', label: 'Utilizado' },
  { value: 'RESERVADO', label: 'Reservado' },
  { value: 'EXPIRADO', label: 'Expirado' },
  { value: 'CANCELADO', label: 'Cancelado' }
]
</script>

<template>
  <BaseCard :padded="false" class="p-4">
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
      <div class="relative sm:col-span-2 xl:col-span-1">
        <MagnifyingGlassIcon
          class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500"
        />
        <input
          v-model="busca"
          type="search"
          placeholder="Buscar por ingresso, participante ou pedido..."
          class="w-full rounded-lg border border-zinc-700 bg-zinc-950 py-2.5 pl-9 pr-3.5 text-sm text-white placeholder-zinc-500 transition-colors focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
        />
      </div>

      <BaseSelect v-model="evento" :options="props.eventos" />
      <BaseSelect v-model="status" :options="statusOptions" />
    </div>
  </BaseCard>
</template>
