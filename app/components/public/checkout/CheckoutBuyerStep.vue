<script setup lang="ts">
import BuyerForm from '~/components/public/checkout/BuyerForm.vue'
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
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <div>
      <h2 class="text-lg font-semibold text-white">Comprador</h2>
      <p class="mt-1 text-sm text-zinc-400">
        Dados de quem está realizando a compra.
      </p>
    </div>

    <BuyerForm
      :comprador="props.comprador"
      :erros="props.erros"
      @update:nome="emit('update:nome', $event)"
      @update:telefone="emit('update:telefone', $event)"
      @update:email="emit('update:email', $event)"
    />
  </section>
</template>
