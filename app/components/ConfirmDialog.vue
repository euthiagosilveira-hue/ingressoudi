<script setup lang="ts">
import { computed } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'

const props = withDefaults(
  defineProps<{
    open: boolean
    title: string
    description?: string
    confirmLabel?: string
    cancelLabel?: string
    tone?: 'default' | 'danger'
    loading?: boolean
  }>(),
  {
    description: '',
    confirmLabel: 'Confirmar',
    cancelLabel: 'Cancelar',
    tone: 'default',
    loading: false
  }
)

const emit = defineEmits<{
  confirm: []
  cancel: []
}>()

const variante = computed(() => (props.tone === 'danger' ? 'danger' : 'primary'))
</script>

<template>
  <BaseModal :open="props.open" :title="props.title" @close="emit('cancel')">
    <p v-if="props.description" class="text-sm text-zinc-400">{{ props.description }}</p>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.loading" @click="emit('cancel')">
          {{ props.cancelLabel }}
        </AppButton>
        <AppButton :variant="variante" :disabled="props.loading" @click="emit('confirm')">
          {{ props.confirmLabel }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
