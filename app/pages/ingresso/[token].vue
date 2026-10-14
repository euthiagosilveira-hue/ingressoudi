<script setup lang="ts">
import { tituloPublico } from '~/utils/marca'
import SharedTicketPage from '~/components/public/compartilhamento/SharedTicketPage.vue'

useSeoMeta({
  title: tituloPublico('Ingresso'),
  description: 'Ingresso compartilhado.'
})
</script>

<template>
  <SharedTicketPage />
</template>
