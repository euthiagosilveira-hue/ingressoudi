<script setup lang="ts">
import { computed } from 'vue'
import type { OrderPriceType } from '~/types/pedido'

const props = defineProps<{
  tipo: OrderPriceType
}>()

const mapa: Record<OrderPriceType, { label: string; classes: string }> = {
  LOTE: {
    label: 'Lote',
    classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300'
  },
  AVULSO: {
    label: 'Avulso',
    classes: 'border-zinc-700 bg-zinc-800/70 text-zinc-300'
  }
}

const info = computed(() => mapa[props.tipo])
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    {{ info.label }}
  </span>
</template>
