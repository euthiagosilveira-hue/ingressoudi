<script setup lang="ts">
import { EyeIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import StatusBadge from '~/components/StatusBadge.vue'
import type { RecentOrder } from '~/types/dashboard'

const props = defineProps<{
  orders: RecentOrder[]
}>()

function paymentStatus(order: RecentOrder) {
  return order.payment === 'Pago' ? 'success' : 'warning'
}

function entranceStatus(order: RecentOrder) {
  if (order.entranceUsed <= 0) return 'danger'
  if (order.entranceUsed >= order.entranceTotal) return 'success'
  return 'warning'
}

function entranceLabel(order: RecentOrder) {
  return `${order.entranceUsed} / ${order.entranceTotal}`
}
</script>

<template>
  <BaseCard :padded="false" class="flex h-full flex-col p-5 sm:p-6">
    <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Últimos pedidos
    </h3>

    <div class="mt-5 flex-1 overflow-x-auto">
      <table class="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr class="text-xs uppercase tracking-wide text-zinc-500">
            <th class="pb-4 pr-4 font-medium">Pedido</th>
            <th class="pb-4 pr-4 font-medium">Comprador</th>
            <th class="pb-4 pr-4 font-medium">Ingressos</th>
            <th class="pb-4 pr-4 font-medium">Total</th>
            <th class="pb-4 pr-4 font-medium">Pagamento</th>
            <th class="pb-4 pr-4 font-medium">Entrada</th>
            <th class="pb-4 font-medium">Ações</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-800">
          <tr v-for="order in props.orders" :key="order.id">
            <td class="py-4 pr-4 align-middle text-zinc-400">{{ order.id }}</td>
            <td class="py-4 pr-4 align-middle font-semibold text-white">{{ order.buyer }}</td>
            <td class="py-4 pr-4 align-middle text-zinc-300">{{ order.tickets }}</td>
            <td class="py-4 pr-4 align-middle text-zinc-300">{{ order.total }}</td>
            <td class="py-4 pr-4 align-middle">
              <StatusBadge :status="paymentStatus(order)" :label="order.payment" />
            </td>
            <td class="py-4 pr-4 align-middle">
              <StatusBadge :status="entranceStatus(order)" :label="entranceLabel(order)" />
            </td>
            <td class="py-4 align-middle">
              <button
                type="button"
                :aria-label="`Visualizar pedido ${order.id}`"
                class="flex h-9 w-9 cursor-pointer items-center justify-center rounded-lg border border-amber-400/60 text-amber-400 transition-colors duration-150 hover:bg-amber-400/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
              >
                <EyeIcon class="h-[18px] w-[18px]" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="mt-6 flex justify-center pt-1">
      <AppButton variant="outline">Ver todos os pedidos</AppButton>
    </div>
  </BaseCard>
</template>
