<script setup lang="ts">
import AdminDashboard from '~/components/AdminDashboard.vue'

definePageMeta({
  title: 'Dashboard',
  description: 'Visão geral do evento de hoje',
  layout: 'dashboard-test-layout',
  middleware: ['admin-auth']
})
</script>

<template>
  <AdminDashboard />
</template>
