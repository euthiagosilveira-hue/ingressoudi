<script setup lang="ts">
import { computed } from 'vue'
import type { EntryState } from '~/types/entrada'

const props = defineProps<{
  state: EntryState
}>()

const mapa: Record<EntryState, { label: string; classes: string }> = {
  ATIVA: {
    label: 'Ativa',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  ANULADA: {
    label: 'Anulada',
    classes: 'border-red-500/30 bg-red-500/10 text-red-300'
  }
}

const info = computed(() => mapa[props.state])
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
