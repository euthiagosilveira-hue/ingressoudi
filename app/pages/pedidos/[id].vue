<script setup lang="ts">
import { onMounted, ref } from 'vue'

import OrderDetails from '~/components/pedidos/OrderDetails.vue'
import OrderNotFound from '~/components/pedidos/OrderNotFound.vue'
import { obterPedidoAdmin } from '~/services/admin/pedidos'
import type { OrderDetail } from '~/types/pedido'
import { mapearPedidoAdminParaDetalhe } from '~/utils/pedidos'

definePageMeta({
  title: 'Detalhe do pedido',
  description: 'Visualize todos os dados do pedido.',
  layout: 'admin-layout',
  sidebarActive: 'Pedidos',
  middleware: ['admin-auth']
})

const route = useRoute()
const pedido = ref<OrderDetail | null>(null)
const carregado = ref(false)

onMounted(async () => {
  try {
    const row = await obterPedidoAdmin(String(route.params.id))
    pedido.value = row ? mapearPedidoAdminParaDetalhe(row) : null
  } catch {
    pedido.value = null
  } finally {
    carregado.value = true
  }
})
</script>

<template>
  <OrderDetails v-if="pedido" :pedido="pedido" />
  <OrderNotFound v-else-if="carregado" />
</template>
