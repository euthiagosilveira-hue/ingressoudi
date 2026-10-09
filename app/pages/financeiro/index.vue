<script setup lang="ts">
import FinancialDashboard from '~/components/financeiro/FinancialDashboard.vue'

definePageMeta({
  title: 'Financeiro',
  description: 'Acompanhe pagamentos, reembolsos e valores dos eventos.',
  layout: 'admin-layout',
  sidebarActive: 'Financeiro',
  middleware: ['admin-auth']
})
</script>

<template>
  <FinancialDashboard />
</template>
