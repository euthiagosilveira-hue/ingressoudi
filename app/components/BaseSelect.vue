<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/24/outline'
import type { SelectOption } from '~/types/ui'

const props = withDefaults(
  defineProps<{
    modelValue: string
    options: SelectOption[]
    label?: string
    id?: string
    name?: string
  }>(),
  {
    label: '',
    id: '',
    name: ''
  }
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const value = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val)
})
</script>

<template>
  <label class="block">
    <span v-if="label" class="mb-1.5 block text-sm font-medium text-zinc-300">
      {{ label }}
    </span>
    <div class="relative">
      <select
        :id="id || name"
        :name="name"
        v-model="value"
        class="w-full cursor-pointer appearance-none rounded-lg border border-zinc-700 bg-zinc-900 px-3.5 py-2.5 pr-10 text-sm text-white transition-colors focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
      >
        <option v-for="option in options" :key="option.value" :value="option.value">
          {{ option.label }}
        </option>
      </select>
      <ChevronDownIcon
        class="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500"
      />
    </div>
  </label>
</template>
