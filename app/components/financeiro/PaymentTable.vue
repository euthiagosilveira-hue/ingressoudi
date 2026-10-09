<script setup lang="ts">
import PaymentTableRow from '~/components/financeiro/PaymentTableRow.vue'
import type { PaymentListItem } from '~/types/pagamento'

const props = defineProps<{
  pagamentos: PaymentListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; action: string }]
}>()
</script>

<template>
  <div class="overflow-x-auto rounded-2xl border border-zinc-800 bg-zinc-900">
    <table class="w-full min-w-[880px] border-collapse text-left">
      <thead>
        <tr class="text-[11px] uppercase tracking-wide text-zinc-500">
          <th scope="col" class="px-4 py-3 font-medium">Pagamento</th>
          <th scope="col" class="px-4 py-3 font-medium">Pedido</th>
          <th scope="col" class="px-4 py-3 font-medium">Comprador</th>
          <th scope="col" class="px-4 py-3 font-medium">Evento</th>
          <th scope="col" class="px-4 py-3 font-medium">Valor</th>
          <th scope="col" class="px-4 py-3 font-medium">Status</th>
          <th scope="col" class="px-4 py-3 font-medium">Data</th>
          <th scope="col" class="px-4 py-3 text-right font-medium">Ações</th>
        </tr>
      </thead>
      <tbody>
        <PaymentTableRow
          v-for="pagamento in props.pagamentos"
          :key="pagamento.id"
          :pagamento="pagamento"
          @action="emit('action', $event)"
        />
      </tbody>
    </table>
  </div>
</template>
