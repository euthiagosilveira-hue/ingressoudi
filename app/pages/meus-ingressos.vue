<script setup lang="ts">
import { tituloPublico } from '~/utils/marca'
import PublicTicketsPage from '~/components/public/ingressos/PublicTicketsPage.vue'

useSeoMeta({
  title: tituloPublico('Meus ingressos'),
  description: 'Acesse e apresente os ingressos do seu pedido.'
})
</script>

<template>
  <PublicTicketsPage />
</template>
