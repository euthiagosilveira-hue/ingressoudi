<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatMoeda, formatNumero } from '~/utils/format'
import type { FinancialSummaryData } from '~/types/pagamento'

const props = defineProps<{
  resumo: FinancialSummaryData
}>()

const cards = computed(() => [
  {
    label: 'Valor aprovado',
    valor: formatMoeda(props.resumo.valorAprovado),
    tone: 'text-amber-400',
    ajuda: 'Bruto confirmado'
  },
  {
    label: 'Pagamentos aprovados',
    valor: formatNumero(props.resumo.aprovados),
    tone: 'text-green-300',
    ajuda: null
  },
  {
    label: 'Pendente',
    valor: formatMoeda(props.resumo.pendente),
    tone: 'text-amber-300',
    ajuda: null
  },
  {
    label: 'Reembolsado',
    valor: formatMoeda(props.resumo.reembolsado),
    tone: 'text-violet-300',
    ajuda: null
  },
  {
    label: 'Valor líquido',
    valor: formatMoeda(props.resumo.liquido),
    tone: 'text-green-300',
    ajuda: 'Antes de taxas do provedor.'
  }
])
</script>

<template>
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
    <BaseCard v-for="card in cards" :key="card.label" :padded="false" class="p-4">
      <p class="text-[11px] uppercase tracking-wide text-zinc-500">{{ card.label }}</p>
      <p class="mt-1 truncate text-lg font-bold" :class="card.tone">{{ card.valor }}</p>
      <p v-if="card.ajuda" class="mt-0.5 text-[10px] text-zinc-600">{{ card.ajuda }}</p>
    </BaseCard>
  </div>
</template>
