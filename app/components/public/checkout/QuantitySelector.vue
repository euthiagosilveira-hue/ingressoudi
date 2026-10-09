<script setup lang="ts">
import { MinusIcon, PlusIcon } from '@heroicons/vue/24/outline'

const props = withDefaults(
  defineProps<{
    modelValue: number
    min?: number
    max?: number
    disabled?: boolean
  }>(),
  { min: 1, max: 10, disabled: false }
)

const emit = defineEmits<{
  'update:modelValue': [value: number]
}>()

const btn =
  'flex h-12 w-12 items-center justify-center rounded-xl border border-zinc-700 text-zinc-200 transition-colors duration-150 hover:border-amber-400/60 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 disabled:cursor-not-allowed disabled:opacity-40'

function diminuir() {
  if (props.modelValue > props.min) emit('update:modelValue', props.modelValue - 1)
}

function aumentar() {
  if (props.modelValue < props.max) emit('update:modelValue', props.modelValue + 1)
}
</script>

<template>
  <div class="inline-flex items-center gap-4">
    <button
      type="button"
      class="cursor-pointer"
      :class="btn"
      aria-label="Diminuir quantidade"
      :disabled="props.disabled || props.modelValue <= props.min"
      @click="diminuir"
    >
      <MinusIcon class="h-5 w-5" />
    </button>

    <span class="w-10 text-center text-2xl font-bold tabular-nums text-white">
      {{ props.modelValue }}
    </span>

    <button
      type="button"
      class="cursor-pointer"
      :class="btn"
      aria-label="Aumentar quantidade"
      :disabled="props.disabled || props.modelValue >= props.max"
      @click="aumentar"
    >
      <PlusIcon class="h-5 w-5" />
    </button>
  </div>
</template>
