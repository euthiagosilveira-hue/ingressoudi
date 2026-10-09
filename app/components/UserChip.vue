<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    name: string
    role?: string
  }>(),
  { role: '' }
)

const initials = computed(() =>
  props.name
    .split(' ')
    .map((word) => word.charAt(0).toUpperCase())
    .slice(0, 2)
    .join('')
)
</script>

<template>
  <div class="flex items-center gap-3">
    <div
      class="flex h-10 w-10 items-center justify-center rounded-full border border-amber-400/50 bg-zinc-800 text-sm font-semibold text-amber-400"
    >
      {{ initials }}
    </div>
    <div class="min-w-0">
      <p class="truncate text-sm font-semibold text-white">{{ name }}</p>
      <p v-if="role" class="truncate text-xs text-zinc-400">{{ role }}</p>
    </div>
  </div>
</template>
