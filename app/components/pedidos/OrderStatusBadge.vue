<script setup lang="ts">
import { computed } from 'vue'
import type { OrderStatus } from '~/types/pedido'

const props = defineProps<{
  status: OrderStatus
}>()

const mapa: Record<OrderStatus, { label: string; classes: string }> = {
  RESERVADO: {
    label: 'Reservado',
    classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300'
  },
  PAGO: {
    label: 'Pago',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  EXPIRADO: {
    label: 'Expirado',
    classes: 'border-zinc-700/40 bg-zinc-800/60 text-zinc-500'
  },
  CANCELADO: {
    label: 'Cancelado',
    classes: 'border-red-500/30 bg-red-500/10 text-red-300'
  }
}

const info = computed(() => mapa[props.status])
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    <span class="h-1.5 w-1.5 rounded-full bg-current opacity-80"></span>
    {{ info.label }}
  </span>
</template>
