<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    status?: 'success' | 'warning' | 'danger' | 'neutral'
    label: string
  }>(),
  { status: 'neutral' }
)

const statusClasses: Record<string, string> = {
  success: 'bg-green-500/15 text-green-400',
  warning: 'bg-amber-500/15 text-amber-400',
  danger: 'bg-red-500/15 text-red-400',
  neutral: 'bg-zinc-800 text-zinc-300'
}

const classes = computed(() => [
  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
  statusClasses[props.status]
])
</script>

<template>
  <span :class="classes">{{ label }}</span>
</template>
