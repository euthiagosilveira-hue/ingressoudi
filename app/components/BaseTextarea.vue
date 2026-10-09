<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    modelValue: string
    label?: string
    placeholder?: string
    rows?: number
    maxlength?: number
    name?: string
    id?: string
    disabled?: boolean
    invalid?: boolean
  }>(),
  {
    label: '',
    placeholder: '',
    rows: 4,
    maxlength: undefined,
    name: '',
    id: '',
    disabled: false,
    invalid: false
  }
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const value = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val)
})

const textareaClasses = computed(() => [
  'w-full resize-y rounded-lg border bg-zinc-900 px-3.5 py-3 text-sm text-white placeholder-zinc-500 transition-colors focus:outline-none focus:ring-2 disabled:cursor-not-allowed disabled:opacity-50',
  props.invalid
    ? 'border-red-500/60 focus:border-red-500 focus:ring-red-500/30'
    : 'border-zinc-700 focus:border-amber-400/60 focus:ring-amber-400/30'
])
</script>

<template>
  <label class="block">
    <span v-if="label" class="mb-1.5 block text-sm font-medium text-zinc-300">
      {{ label }}
    </span>
    <textarea
      :id="id || name"
      :name="name"
      :rows="rows"
      :maxlength="maxlength"
      :placeholder="placeholder"
      :disabled="disabled"
      :aria-invalid="invalid || undefined"
      v-model="value"
      :class="textareaClasses"
    ></textarea>
  </label>
</template>
