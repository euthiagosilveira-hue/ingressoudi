<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatMoeda, formatNumero } from '~/utils/format'
import type { OrderSummaryData } from '~/types/pedido'

const props = defineProps<{
  resumo: OrderSummaryData
}>()

const cards = computed(() => [
  {
    label: 'Pedidos',
    valor: formatNumero(props.resumo.total),
    tone: 'text-white'
  },
  {
    label: 'Pagos',
    valor: formatNumero(props.resumo.pagos),
    tone: 'text-green-300'
  },
  {
    label: 'Reservados',
    valor: formatNumero(props.resumo.reservados),
    tone: 'text-amber-300'
  },
  {
    label: 'Expirados',
    valor: formatNumero(props.resumo.expirados),
    tone: 'text-zinc-400'
  },
  {
    label: 'Valor pago',
    valor: formatMoeda(props.resumo.valorPago),
    tone: 'text-amber-400'
  }
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
