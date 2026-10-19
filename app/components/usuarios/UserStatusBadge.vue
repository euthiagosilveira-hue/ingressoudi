<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  ativo: boolean
  pendente?: boolean
}>()

const info = computed(() => {
  if (props.ativo && props.pendente) {
    return { label: 'Convite pendente', classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300' }
  }
  return props.ativo
    ? { label: 'Ativo', classes: 'border-green-500/30 bg-green-500/10 text-green-300' }
    : { label: 'Inativo', classes: 'border-zinc-600/40 bg-zinc-700/30 text-zinc-400' }
})
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    <span class="h-1.5 w-1.5 rounded-full bg-current opacity-80"></span>
    {{ info.label }}
  </span>
</template>
