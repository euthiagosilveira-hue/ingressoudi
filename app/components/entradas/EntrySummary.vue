<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatNumero } from '~/utils/format'
import type { EntrySummaryData } from '~/types/entrada'

const props = defineProps<{
  resumo: EntrySummaryData
}>()

const cards = computed(() => [
  { label: 'Entradas', valor: formatNumero(props.resumo.total), tone: 'text-white' },
  { label: 'Ativas', valor: formatNumero(props.resumo.ativas), tone: 'text-green-300' },
  { label: 'Anuladas', valor: formatNumero(props.resumo.anuladas), tone: 'text-red-300' },
  { label: 'Por QR Code', valor: formatNumero(props.resumo.qrCode), tone: 'text-amber-300' },
  { label: 'Por nome', valor: formatNumero(props.resumo.nome), tone: 'text-zinc-200' }
])
</script>

<template>
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
    <BaseCard v-for="card in cards" :key="card.label" :padded="false" class="p-4">
      <p class="text-[11px] uppercase tracking-wide text-zinc-500">{{ card.label }}</p>
      <p class="mt-1 truncate text-lg font-bold" :class="card.tone">{{ card.valor }}</p>
    </BaseCard>
  </div>
</template>
