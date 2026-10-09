<script setup lang="ts">
import { ref, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import FormField from '~/components/FormField.vue'
import type { EntryListItem } from '~/types/entrada'

const props = defineProps<{
  open: boolean
  entrada: EntryListItem | null
}>()

const emit = defineEmits<{
  confirm: [motivo: string]
  cancel: []
}>()

const motivo = ref('')
const erro = ref('')

watch(
  () => props.open,
  (aberto) => {
    if (aberto) {
      motivo.value = ''
      erro.value = ''
    }
  }
)

function confirmar() {
  const texto = motivo.value.trim()
  if (texto.length < 3) {
    erro.value = 'Informe o motivo da anulação (mínimo 3 caracteres).'
    return
  }
  emit('confirm', texto)
}
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Anular entrada"
    :subtitle="props.entrada?.ingressoCodigo ?? ''"
    @close="emit('cancel')"
  >
    <div class="space-y-4">
      <p class="text-sm text-zinc-400">
        Esta ação preservará o registro da entrada, mas ela deixará de ser considerada ativa.
      </p>

      <FormField label="Motivo da anulação" required :error="erro">
        <BaseTextarea
          v-model="motivo"
          placeholder="Descreva o motivo da anulação..."
          :invalid="!!erro"
        />
      </FormField>
    </div>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" @click="emit('cancel')">Cancelar</AppButton>
        <AppButton variant="danger" @click="confirmar">Anular entrada</AppButton>
      </div>
    </template>
  </BaseModal>
</template>
