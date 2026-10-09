<script setup lang="ts">
import EntryList from '~/components/entradas/EntryList.vue'

definePageMeta({
  title: 'Entradas',
  description: 'Consulte e audite os acessos registrados nos eventos.',
  layout: 'admin-layout',
  sidebarActive: 'Entradas',
  middleware: ['admin-auth']
})
</script>

<template>
  <EntryList />
</template>
