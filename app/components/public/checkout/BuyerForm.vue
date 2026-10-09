<script setup lang="ts">
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import { formatarTelefone } from '~/utils/checkout'
import type { CheckoutBuyer, CheckoutBuyerErrors } from '~/types/checkout'

const props = defineProps<{
  comprador: CheckoutBuyer
  erros: CheckoutBuyerErrors
}>()

const emit = defineEmits<{
  'update:nome': [value: string]
  'update:telefone': [value: string]
  'update:email': [value: string]
}>()

function aoTelefone(valor: string) {
  emit('update:telefone', formatarTelefone(valor))
}
</script>

<template>
  <div class="space-y-4">
    <FormField label="Nome completo" required :error="props.erros.nome">
      <BaseInput
        :model-value="props.comprador.nome"
        autocomplete="name"
        placeholder="Seu nome completo"
        :invalid="!!props.erros.nome"
        @update:model-value="emit('update:nome', $event)"
      />
    </FormField>

    <FormField label="Telefone" required :error="props.erros.telefone">
      <BaseInput
        :model-value="props.comprador.telefone"
        autocomplete="tel"
        placeholder="(11) 99999-9999"
        :invalid="!!props.erros.telefone"
        @update:model-value="aoTelefone"
      />
    </FormField>

    <FormField label="E-mail" required :error="props.erros.email">
      <BaseInput
        :model-value="props.comprador.email"
        autocomplete="email"
        type="email"
        placeholder="voce@email.com"
        :invalid="!!props.erros.email"
        @update:model-value="emit('update:email', $event)"
      />
    </FormField>
  </div>
</template>
