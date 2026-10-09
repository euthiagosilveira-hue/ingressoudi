<script setup lang="ts">
import { ClockIcon } from '@heroicons/vue/24/outline'

defineProps<{
  texto: string
}>()
</script>

<template>
  <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
    <div class="flex items-center justify-between gap-3">
      <span class="inline-flex items-center gap-2 text-sm text-zinc-400">
        <ClockIcon class="h-4 w-4 text-amber-400" />
        Expira em
      </span>
      <span class="text-2xl font-bold tabular-nums text-amber-400">{{ texto }}</span>
    </div>
  </div>
</template>
