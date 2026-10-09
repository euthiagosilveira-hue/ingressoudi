<script setup lang="ts">
withDefaults(
  defineProps<{
    label?: string
    required?: boolean
    error?: string
    hint?: string
    htmlFor?: string
  }>(),
  {
    label: '',
    required: false,
    error: '',
    hint: '',
    htmlFor: ''
  }
)
</script>

<template>
  <div>
    <label
      v-if="label"
      :for="htmlFor || undefined"
      class="mb-1.5 block text-sm font-medium text-zinc-300"
    >
      {{ label }}<span v-if="required" class="ml-0.5 text-amber-400">*</span>
    </label>
    <slot />
    <p v-if="error" class="mt-1.5 text-xs text-red-400">{{ error }}</p>
    <p v-else-if="hint" class="mt-1.5 text-xs text-zinc-500">{{ hint }}</p>
  </div>
</template>
