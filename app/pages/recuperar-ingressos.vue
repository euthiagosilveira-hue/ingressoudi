<script setup lang="ts">
import { tituloPublico } from '~/utils/marca'
import PublicRecoveryPage from '~/components/public/recuperacao/PublicRecoveryPage.vue'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: tituloPublico('Recuperar ingressos'),
  description: 'Recupere seus ingressos usando o código do pedido e o telefone da compra.'
})
</script>

<template>
  <PublicRecoveryPage />
</template>
