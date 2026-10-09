<script setup lang="ts">
import { computed } from 'vue'
import { MagnifyingGlassIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import type { SelectOption } from '~/types/ui'
import type {
  FinancialFiltersState,
  FinancialPeriodFilter,
  FinancialStatusFilter
} from '~/types/pagamento'

const props = defineProps<{
  modelValue: FinancialFiltersState
  eventos: SelectOption[]
}>()

const emit = defineEmits<{
  'update:modelValue': [value: FinancialFiltersState]
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
    emit('update:modelValue', { ...props.modelValue, status: valor as FinancialStatusFilter })
})

const periodo = computed({
  get: () => props.modelValue.periodo,
  set: (valor: string) =>
    emit('update:modelValue', { ...props.modelValue, periodo: valor as FinancialPeriodFilter })
})

const statusOptions: SelectOption[] = [
  { value: 'TODOS', label: 'Todos os status' },
  { value: 'PENDENTE', label: 'Pendente' },
  { value: 'APROVADO', label: 'Aprovado' },
  { value: 'REJEITADO', label: 'Rejeitado' },
  { value: 'CANCELADO', label: 'Cancelado' },
  { value: 'EXPIRADO', label: 'Expirado' },
  { value: 'REEMBOLSADO', label: 'Reembolsado' }
]

const periodoOptions: SelectOption[] = [
  { value: 'TODAS', label: 'Todas as datas' },
  { value: 'HOJE', label: 'Hoje' },
  { value: 'SETE_DIAS', label: 'Últimos 7 dias' },
  { value: 'TRINTA_DIAS', label: 'Últimos 30 dias' }
]
</script>

<template>
  <BaseCard :padded="false" class="p-4">
    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <div class="relative sm:col-span-2 xl:col-span-1">
        <MagnifyingGlassIcon
          class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500"
        />
        <input
          v-model="busca"
          type="search"
          placeholder="Buscar pedido, comprador ou transação..."
          class="w-full rounded-lg border border-zinc-700 bg-zinc-950 py-2.5 pl-9 pr-3.5 text-sm text-white placeholder-zinc-500 transition-colors focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
        />
      </div>

      <BaseSelect v-model="evento" :options="props.eventos" />
      <BaseSelect v-model="status" :options="statusOptions" />
      <BaseSelect v-model="periodo" :options="periodoOptions" />
    </div>
  </BaseCard>
</template>
