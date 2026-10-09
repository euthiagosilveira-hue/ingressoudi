<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string
    subtitle?: string
  }>(),
  { subtitle: '' }
)
</script>

<template>
  <header class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
    <div>
      <h1 class="text-2xl font-bold text-white">{{ title }}</h1>
      <p v-if="subtitle" class="mt-1 text-sm text-zinc-400">{{ subtitle }}</p>
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <slot name="actions" />
    </div>
  </header>
</template>
