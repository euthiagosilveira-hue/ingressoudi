<script setup lang="ts">
import { computed } from 'vue'
import type { PublicationStatus } from '~/types/evento'

const props = defineProps<{
  status: PublicationStatus
}>()

const mapa: Record<PublicationStatus, { label: string; classes: string }> = {
  PUBLICADO: {
    label: 'Publicado',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  RASCUNHO: {
    label: 'Rascunho',
    classes: 'border-zinc-600/40 bg-zinc-800/80 text-zinc-300'
  }
}

const info = computed(() => mapa[props.status])
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide backdrop-blur-sm"
    :class="info.classes"
  >
    {{ info.label }}
  </span>
</template>
