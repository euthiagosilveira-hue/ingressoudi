<script setup lang="ts">
import { tituloPublico } from '~/utils/marca'
import PublicRecoveryPage from '~/components/public/recuperacao/PublicRecoveryPage.vue'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: tituloPublico('Recuperar ingressos'),
  description: 'Encontre seus ingressos pelo telefone e e-mail da compra.'
})
</script>

<template>
  <PublicRecoveryPage />
</template>
