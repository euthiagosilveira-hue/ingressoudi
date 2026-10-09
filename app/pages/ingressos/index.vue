<script setup lang="ts">
import TicketList from '~/components/ingressos/TicketList.vue'

definePageMeta({
  title: 'Ingressos',
  description: 'Consulte ingressos emitidos, status e utilização nos eventos.',
  layout: 'admin-layout',
  sidebarActive: 'Ingressos',
  middleware: ['admin-auth']
})
</script>

<template>
  <TicketList />
</template>
