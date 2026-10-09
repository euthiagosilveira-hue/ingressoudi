<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  disponiveis: number | null
}>()

const exibir = computed(() => props.disponiveis !== null && props.disponiveis > 0)
const baixo = computed(() => props.disponiveis !== null && props.disponiveis <= 10)

const texto = computed(() => {
  if (baixo.value) return 'Últimos ingressos'
  return `${props.disponiveis} ingressos disponíveis`
})
</script>

<template>
  <p
    v-if="exibir"
    class="inline-flex items-center gap-2 text-sm"
    :class="baixo ? 'text-amber-300' : 'text-zinc-300'"
  >
    <span class="h-2 w-2 rounded-full" :class="baixo ? 'bg-amber-400' : 'bg-green-400'"></span>
    {{ texto }}
  </p>
</template>
