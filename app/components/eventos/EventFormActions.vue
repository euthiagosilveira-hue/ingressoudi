<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'

withDefaults(
  defineProps<{
    submitting?: boolean
    disabled?: boolean
  }>(),
  {
    submitting: false,
    disabled: false
  }
)

const emit = defineEmits<{
  cancel: []
  submit: []
}>()
</script>

<template>
  <BaseCard class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
    <AppButton variant="ghost" :disabled="submitting" @click="emit('cancel')">
      Cancelar
    </AppButton>

    <AppButton
      variant="primary"
      :disabled="disabled || submitting"
      @click="emit('submit')"
    >
      {{ submitting ? 'Salvando...' : 'Salvar evento' }}
    </AppButton>
  </BaseCard>
</template>
