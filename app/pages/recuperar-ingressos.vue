<script setup lang="ts">
import PublicRecoveryPage from '~/components/public/recuperacao/PublicRecoveryPage.vue'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: 'Recuperar ingressos | GZ1 Ingresso',
  description: 'Recupere seus ingressos usando o código do pedido e o telefone da compra.'
})
</script>

<template>
  <PublicRecoveryPage />
</template>
