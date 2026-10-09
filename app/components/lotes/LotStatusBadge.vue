<script setup lang="ts">
import { computed } from 'vue'
import type { LotStatus } from '~/types/lote'

const props = defineProps<{
  status: LotStatus
}>()

const mapa: Record<LotStatus, { label: string; classes: string }> = {
  INATIVO: {
    label: 'Inativo',
    classes: 'border-zinc-600/40 bg-zinc-800/80 text-zinc-300'
  },
  ATIVO: {
    label: 'Ativo',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  ENCERRADO: {
    label: 'Encerrado',
    classes: 'border-zinc-700/40 bg-zinc-800/50 text-zinc-500'
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
