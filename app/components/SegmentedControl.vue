<script setup lang="ts">
import type { SelectOption } from '~/types/ui'

withDefaults(
  defineProps<{
    modelValue: string
    options: SelectOption[]
    name?: string
    disabled?: boolean
  }>(),
  {
    name: '',
    disabled: false
  }
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()
</script>

<template>
  <div
    class="inline-flex flex-wrap gap-1 rounded-lg border border-zinc-700 bg-zinc-950 p-1"
    role="group"
  >
    <button
      v-for="option in options"
      :key="option.value"
      type="button"
      :disabled="disabled"
      :aria-pressed="modelValue === option.value"
      class="cursor-pointer rounded-md px-4 py-1.5 text-xs font-semibold uppercase tracking-wide transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 disabled:cursor-not-allowed disabled:opacity-50"
      :class="
        modelValue === option.value
          ? 'bg-amber-400 text-zinc-950'
          : 'text-zinc-400 hover:text-zinc-100'
      "
      @click="emit('update:modelValue', option.value)"
    >
      {{ option.label }}
    </button>
  </div>
</template>
