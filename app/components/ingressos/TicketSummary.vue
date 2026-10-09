<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatNumero } from '~/utils/format'
import type { TicketSummaryData } from '~/types/ingresso'

const props = defineProps<{
  resumo: TicketSummaryData
}>()

const cards = computed(() => [
  { label: 'Ingressos', valor: formatNumero(props.resumo.total), tone: 'text-white' },
  { label: 'Válidos', valor: formatNumero(props.resumo.validos), tone: 'text-green-300' },
  { label: 'Utilizados', valor: formatNumero(props.resumo.utilizados), tone: 'text-zinc-200' },
  { label: 'Reservados', valor: formatNumero(props.resumo.reservados), tone: 'text-amber-300' },
  { label: 'Cancelados', valor: formatNumero(props.resumo.cancelados), tone: 'text-red-300' },
  { label: 'Expirados', valor: formatNumero(props.resumo.expirados), tone: 'text-zinc-400' }
])
</script>

<template>
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
    <BaseCard v-for="card in cards" :key="card.label" :padded="false" class="p-4">
      <p class="text-[11px] uppercase tracking-wide text-zinc-500">{{ card.label }}</p>
      <p class="mt-1 truncate text-lg font-bold" :class="card.tone">{{ card.valor }}</p>
    </BaseCard>
  </div>
</template>
