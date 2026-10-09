<script setup lang="ts">
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'

const props = defineProps<{
  indice: number
  modelValue: string
  error?: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()
</script>

<template>
  <FormField :label="`Ingresso ${props.indice + 1}`" required :error="props.error">
    <BaseInput
      :model-value="props.modelValue"
      placeholder="Nome do participante"
      autocomplete="off"
      :invalid="!!props.error"
      @update:model-value="emit('update:modelValue', $event)"
    />
  </FormField>
</template>
