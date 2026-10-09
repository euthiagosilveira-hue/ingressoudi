<script setup lang="ts">
import OrderTableRow from '~/components/pedidos/OrderTableRow.vue'
import type { OrderListItem } from '~/types/pedido'

const props = defineProps<{
  pedidos: OrderListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; action: string }]
}>()
</script>

<template>
  <div class="overflow-x-auto rounded-2xl border border-zinc-800 bg-zinc-900">
    <table class="w-full min-w-[760px] border-collapse text-left">
      <thead>
        <tr class="text-[11px] uppercase tracking-wide text-zinc-500">
          <th class="px-4 py-3 font-medium">Pedido</th>
          <th class="px-4 py-3 font-medium">Comprador</th>
          <th class="px-4 py-3 font-medium">Evento</th>
          <th class="px-4 py-3 font-medium">Qtd.</th>
          <th class="px-4 py-3 font-medium">Valor</th>
          <th class="px-4 py-3 font-medium">Status</th>
          <th class="px-4 py-3 font-medium">Data</th>
          <th class="px-4 py-3 text-right font-medium">Ações</th>
        </tr>
      </thead>
      <tbody>
        <OrderTableRow
          v-for="pedido in props.pedidos"
          :key="pedido.id"
          :pedido="pedido"
          @action="emit('action', { id: pedido.id, action: $event })"
        />
      </tbody>
    </table>
  </div>
</template>
