<script setup lang="ts">
import OrderMobileCard from '~/components/pedidos/OrderMobileCard.vue'
import type { OrderListItem } from '~/types/pedido'

const props = defineProps<{
  pedidos: OrderListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; action: string }]
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <OrderMobileCard
      v-for="pedido in props.pedidos"
      :key="pedido.id"
      :pedido="pedido"
      @action="emit('action', { id: pedido.id, action: $event })"
    />
  </div>
</template>
