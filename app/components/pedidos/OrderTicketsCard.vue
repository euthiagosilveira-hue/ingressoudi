<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import OrderTicketItem from '~/components/pedidos/OrderTicketItem.vue'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()

const emit = defineEmits<{
  visualizar: [id: string]
}>()
</script>

<template>
  <BaseCard id="order-tickets" class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Ingressos</h2>
      <span class="text-xs text-zinc-500">{{ props.pedido.ingressos.length }}</span>
    </div>

    <p v-if="props.pedido.ingressos.length === 0" class="text-sm text-zinc-500">
      Nenhum ingresso emitido para este pedido.
    </p>

    <div v-else class="space-y-3">
      <OrderTicketItem
        v-for="ingresso in props.pedido.ingressos"
        :key="ingresso.id"
        :ingresso="ingresso"
        @visualizar="emit('visualizar', ingresso.id)"
      />
    </div>
  </BaseCard>
</template>
