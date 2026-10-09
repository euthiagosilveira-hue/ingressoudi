<script setup lang="ts">
import { computed } from 'vue'
import type { TicketStatus } from '~/types/ingresso'

const props = defineProps<{
  status: TicketStatus
}>()

const mapa: Record<TicketStatus, { label: string; classes: string }> = {
  RESERVADO: {
    label: 'Reservado',
    classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300'
  },
  VALIDO: {
    label: 'Válido',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  UTILIZADO: {
    label: 'Utilizado',
    classes: 'border-zinc-500/40 bg-zinc-700/40 text-zinc-200'
  },
  EXPIRADO: {
    label: 'Expirado',
    classes: 'border-zinc-700/40 bg-zinc-800/50 text-zinc-500'
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
    class="inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    {{ info.label }}
  </span>
</template>
