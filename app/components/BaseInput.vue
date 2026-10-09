<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    modelValue: string | number
    label?: string
    type?: string
    placeholder?: string
    name?: string
    id?: string
    disabled?: boolean
    required?: boolean
    autocomplete?: string
    invalid?: boolean
    prefix?: string
  }>(),
  {
    label: '',
    type: 'text',
    placeholder: '',
    name: '',
    id: '',
    disabled: false,
    required: false,
    autocomplete: 'off',
    invalid: false,
    prefix: ''
  }
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
  blur: []
  focus: []
}>()

const value = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val)
})

const inputClasses = computed(() => [
  'w-full rounded-lg border bg-zinc-900 px-3.5 py-2.5 text-sm text-white placeholder-zinc-500 transition-colors focus:outline-none focus:ring-2 disabled:cursor-not-allowed disabled:opacity-50',
  props.invalid
    ? 'border-red-500/60 focus:border-red-500 focus:ring-red-500/30'
    : 'border-zinc-700 focus:border-amber-400/60 focus:ring-amber-400/30',
  props.type === 'date' || props.type === 'time' ? '[color-scheme:dark] accent-amber-400' : ''
])
</script>

<template>
  <label class="block">
    <span v-if="label" class="mb-1.5 block text-sm font-medium text-zinc-300">
      {{ label }}
    </span>
    <div class="relative">
      <span
        v-if="prefix"
        class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-zinc-500"
      >
        {{ prefix }}
      </span>
      <input
        :id="id || name"
        :type="type"
        :name="name"
        :placeholder="placeholder"
        :disabled="disabled"
        :required="required"
        :autocomplete="autocomplete"
        :aria-invalid="invalid || undefined"
        v-model="value"
        :class="[inputClasses, prefix ? 'pl-10' : '']"
        @blur="emit('blur')"
        @focus="emit('focus')"
      />
    </div>
  </label>
</template>
