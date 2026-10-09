<script setup lang="ts">
import { reactive, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import FormField from '~/components/FormField.vue'
import type { VipFormValue, VipPayload } from '~/types/vip'
import { montarPayloadVip, validarVip } from '~/utils/vip'

const props = withDefaults(
  defineProps<{
    open: boolean
    mode?: 'create' | 'edit'
    initialValue?: VipFormValue | null
    submitting?: boolean
  }>(),
  { mode: 'create', initialValue: null, submitting: false }
)

const emit = defineEmits<{
  submit: [payload: VipPayload]
  cancel: []
}>()

const valor = reactive<VipFormValue>({ nome: '', telefone: '', observacao: '' })
const erros = reactive<{ nome?: string }>({})

watch(
  () => props.open,
  (aberto) => {
    if (!aberto) return
    valor.nome = props.initialValue?.nome ?? ''
    valor.telefone = props.initialValue?.telefone ?? ''
    valor.observacao = props.initialValue?.observacao ?? ''
    delete erros.nome
  }
)

function enviar() {
  delete erros.nome
  const validacao = validarVip(valor)
  Object.assign(erros, validacao)
  if (Object.keys(validacao).length > 0) return
  emit('submit', montarPayloadVip(valor))
}
</script>

<template>
  <BaseModal
    :open="props.open"
    :title="props.mode === 'edit' ? 'Editar convidado VIP' : 'Adicionar à lista VIP'"
    subtitle="Sem valor, sem lote e sem pagamento."
    @close="emit('cancel')"
  >
    <form class="space-y-4" novalidate @submit.prevent="enviar">
      <FormField label="Nome" required :error="erros.nome">
        <BaseInput v-model="valor.nome" placeholder="Nome do convidado" />
      </FormField>

      <FormField label="Telefone (opcional)">
        <BaseInput v-model="valor.telefone" placeholder="(11) 99999-0000" />
      </FormField>

      <FormField label="Observação (opcional)">
        <BaseTextarea v-model="valor.observacao" :rows="2" placeholder="Ex.: camarote, mesa 4" />
      </FormField>
    </form>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.submitting" @click="emit('cancel')">
          Cancelar
        </AppButton>
        <AppButton variant="primary" :disabled="props.submitting" @click="enviar">
          {{ props.submitting ? 'Salvando...' : props.mode === 'edit' ? 'Salvar' : 'Adicionar' }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
