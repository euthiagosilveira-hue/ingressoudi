<script setup lang="ts">
import { computed } from 'vue'
import type { EventStatus } from '~/types/evento'

const props = defineProps<{
  status: EventStatus
}>()

const mapa: Partial<Record<EventStatus, { label: string; classes: string }>> = {
  CANCELADO: {
    label: 'Evento cancelado',
    classes: 'border-red-500/40 bg-red-500/15 text-red-200'
  },
  EM_ANDAMENTO: {
    label: 'Em andamento',
    classes: 'border-green-500/40 bg-green-500/15 text-green-200'
  },
  REALIZADO: {
    label: 'Encerrado',
    classes: 'border-zinc-600/50 bg-zinc-800/80 text-zinc-300'
  }
}

const info = computed(() => mapa[props.status] ?? null)
</script>

<template>
  <span
    v-if="info"
    class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-[11px] font-bold uppercase tracking-wide backdrop-blur-sm"
    :class="info.classes"
  >
    <span class="h-1.5 w-1.5 rounded-full bg-current opacity-80"></span>
    {{ info.label }}
  </span>
</template>
