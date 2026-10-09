<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import OrderActions from '~/components/pedidos/OrderActions.vue'
import OrderPriceTypeBadge from '~/components/pedidos/OrderPriceTypeBadge.vue'
import OrderStatusBadge from '~/components/pedidos/OrderStatusBadge.vue'
import { formatDataNumerica, formatHora, formatMoeda, formatNumero } from '~/utils/format'
import type { OrderListItem } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderListItem
}>()

const emit = defineEmits<{
  action: [action: string]
}>()

const ehReservado = computed(() => props.pedido.status === 'RESERVADO')
</script>

<template>
  <BaseCard class="flex flex-col gap-3">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <span class="truncate text-sm font-semibold text-white">{{ props.pedido.codigo }}</span>
          <OrderPriceTypeBadge :tipo="props.pedido.tipoPreco" />
        </div>
        <p class="mt-1 truncate text-sm text-zinc-200">{{ props.pedido.compradorNome }}</p>
        <p class="truncate text-xs text-zinc-500">{{ props.pedido.eventoNome }}</p>
      </div>
      <OrderStatusBadge :status="props.pedido.status" />
    </div>

    <div class="flex items-end justify-between gap-3 border-t border-zinc-800 pt-3">
      <div>
        <p class="text-sm text-zinc-200">{{ formatNumero(props.pedido.quantidade) }} ingressos</p>
        <p class="text-xs text-zinc-500">{{ props.pedido.loteNome ?? 'Venda avulsa' }}</p>
        <p
          v-if="props.pedido.pagamentoProvedor === 'DINHEIRO'"
          class="text-[11px] font-semibold uppercase tracking-wide text-emerald-400"
        >
          Dinheiro
        </p>
      </div>
      <p class="text-lg font-bold text-amber-400">{{ formatMoeda(props.pedido.valorTotal) }}</p>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-xs text-zinc-500">
      <span>{{ formatDataNumerica(props.pedido.criadoEm) }} • {{ formatHora(props.pedido.criadoEm) }}</span>
      <span
        v-if="ehReservado && props.pedido.reservaExpiraEm"
        class="text-amber-300/80"
      >
        Expira às {{ formatHora(props.pedido.reservaExpiraEm) }}
      </span>
    </div>

    <div class="border-t border-zinc-800 pt-3">
      <OrderActions inline @action="emit('action', $event)" />
    </div>
  </BaseCard>
</template>
