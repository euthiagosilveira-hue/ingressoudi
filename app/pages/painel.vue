<script setup lang="ts">
import AdminDashboard from '~/components/AdminDashboard.vue'

definePageMeta({
  title: 'Dashboard',
  description: 'Visão geral das vendas e entradas da sua organização',
  layout: 'dashboard-test-layout',
  middleware: ['admin-auth']
})
</script>

<template>
  <AdminDashboard />
</template>
