<script setup lang="ts">
import OrderList from '~/components/pedidos/OrderList.vue'

definePageMeta({
  title: 'Pedidos',
  description: 'Acompanhe reservas, pagamentos e vendas dos eventos.',
  layout: 'admin-layout',
  sidebarActive: 'Pedidos',
  middleware: ['admin-auth']
})
</script>

<template>
  <OrderList />
</template>
