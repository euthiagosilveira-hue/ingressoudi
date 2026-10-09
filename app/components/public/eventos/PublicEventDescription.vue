<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  descricao: string
}>()

const paragrafos = computed(() =>
  props.descricao
    .split(/\n{2,}/)
    .map((paragrafo) => paragrafo.trim())
    .filter(Boolean)
)
</script>

<template>
  <section class="rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-7">
    <h2 class="text-lg font-semibold text-white">Sobre o evento</h2>
    <div class="mt-3 space-y-3 text-sm leading-relaxed text-zinc-300 sm:text-base">
      <p v-for="(paragrafo, indice) in paragrafos" :key="indice">{{ paragrafo }}</p>
    </div>
  </section>
</template>
