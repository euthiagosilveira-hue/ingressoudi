<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'

withDefaults(
  defineProps<{
    submitLabel?: string
    submitting?: boolean
  }>(),
  {
    submitLabel: 'Salvar lote',
    submitting: false
  }
)

const emit = defineEmits<{
  cancel: []
}>()
</script>

<template>
  <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
    <AppButton variant="ghost" type="button" :disabled="submitting" @click="emit('cancel')">
      Cancelar
    </AppButton>
    <AppButton variant="primary" type="submit" :disabled="submitting">
      {{ submitting ? 'Salvando...' : submitLabel }}
    </AppButton>
  </div>
</template>
