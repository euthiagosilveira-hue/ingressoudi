<script setup lang="ts">
import { computed } from 'vue'
import { MagnifyingGlassIcon } from '@heroicons/vue/24/outline'

import BaseSelect from '~/components/BaseSelect.vue'
import type { SelectOption } from '~/types/ui'
import type {
  EventFiltersState,
  EventPublicationFilter,
  EventStatusFilter
} from '~/types/evento'

const props = defineProps<{
  modelValue: EventFiltersState
}>()

const emit = defineEmits<{
  'update:modelValue': [value: EventFiltersState]
}>()

const busca = computed({
  get: () => props.modelValue.busca,
  set: (valor: string) => emit('update:modelValue', { ...props.modelValue, busca: valor })
})

const publicacao = computed({
  get: () => props.modelValue.publicacao,
  set: (valor: string) =>
    emit('update:modelValue', {
      ...props.modelValue,
      publicacao: valor as EventPublicationFilter
    })
})

const statusPills: { value: EventStatusFilter; label: string }[] = [
  { value: 'TODOS', label: 'Todos' },
  { value: 'AGENDADO', label: 'Agendados' },
  { value: 'EM_ANDAMENTO', label: 'Em andamento' },
  { value: 'REALIZADO', label: 'Realizados' },
  { value: 'CANCELADO', label: 'Cancelados' }
]

const publicacaoOptions: SelectOption[] = [
  { value: 'TODOS', label: 'Todos' },
  { value: 'PUBLICADO', label: 'Publicados' },
  { value: 'RASCUNHO', label: 'Rascunhos' }
]

function selecionarStatus(status: EventStatusFilter) {
  emit('update:modelValue', { ...props.modelValue, status })
}
</script>

<template>
  <div
    class="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-4 lg:flex-row lg:items-center lg:justify-between"
  >
    <div class="relative w-full lg:max-w-xs">
      <MagnifyingGlassIcon
        class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500"
      />
      <input
        v-model="busca"
        type="search"
        placeholder="Buscar eventos..."
        class="w-full rounded-lg border border-zinc-700 bg-zinc-950 py-2.5 pl-9 pr-3.5 text-sm text-white placeholder-zinc-500 transition-colors focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
      />
    </div>

    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between lg:justify-end">
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="pill in statusPills"
          :key="pill.value"
          type="button"
          class="cursor-pointer rounded-full border px-3.5 py-1.5 text-xs font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/40"
          :class="
            props.modelValue.status === pill.value
              ? 'border-amber-400/50 bg-amber-400/10 text-amber-300'
              : 'border-zinc-700 text-zinc-400 hover:border-zinc-600 hover:text-zinc-200'
          "
          @click="selecionarStatus(pill.value)"
        >
          {{ pill.label }}
        </button>
      </div>

      <div class="w-full sm:w-44">
        <BaseSelect v-model="publicacao" :options="publicacaoOptions" />
      </div>
    </div>
  </div>
</template>
