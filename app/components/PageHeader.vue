<script setup lang="ts">
import AjudaLink from '~/components/ajuda/AjudaLink.vue'

withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    /** Slug do artigo da central de ajuda sobre esta tela. */
    ajuda?: string
  }>(),
  { subtitle: '', ajuda: '' }
)
</script>

<template>
  <header class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
    <div>
      <h1 class="text-2xl font-bold text-white">{{ title }}</h1>
      <p v-if="subtitle" class="mt-1 text-sm text-zinc-400">{{ subtitle }}</p>
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <AjudaLink v-if="ajuda" :artigo="ajuda" />
      <slot name="actions" />
    </div>
  </header>
</template>
