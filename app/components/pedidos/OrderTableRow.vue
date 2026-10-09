<script setup lang="ts">
import { computed } from 'vue'

import OrderActions from '~/components/pedidos/OrderActions.vue'
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
  <tr
    class="cursor-pointer border-t border-zinc-800 transition-colors duration-150 hover:bg-zinc-800/40"
    @click="emit('action', 'ver')"
  >
    <td class="px-4 py-3">
      <p class="text-sm font-semibold text-white">{{ props.pedido.codigo }}</p>
      <p class="text-xs text-zinc-500">{{ props.pedido.loteNome ?? 'Venda avulsa' }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-200">{{ props.pedido.compradorNome }}</p>
      <p class="text-xs text-zinc-500">{{ props.pedido.telefone }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ props.pedido.eventoNome }}</p>
    </td>

    <td class="px-4 py-3">
      <span class="text-sm text-zinc-200">{{ formatNumero(props.pedido.quantidade) }}</span>
      <span class="ml-1 text-xs text-zinc-500">ingressos</span>
    </td>

    <td class="px-4 py-3">
      <span class="text-sm font-semibold text-amber-400">
        {{ formatMoeda(props.pedido.valorTotal) }}
      </span>
    </td>

    <td class="px-4 py-3">
      <OrderStatusBadge :status="props.pedido.status" />
      <p
        v-if="ehReservado && props.pedido.reservaExpiraEm"
        class="mt-1 text-[11px] text-amber-300/80"
      >
        Expira às {{ formatHora(props.pedido.reservaExpiraEm) }}
      </p>
      <p
        v-if="props.pedido.pagamentoProvedor === 'DINHEIRO'"
        class="mt-1 text-[11px] font-semibold uppercase tracking-wide text-emerald-400"
      >
        Dinheiro
      </p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ formatDataNumerica(props.pedido.criadoEm) }}</p>
      <p class="text-xs text-zinc-500">{{ formatHora(props.pedido.criadoEm) }}</p>
    </td>

    <td class="px-4 py-3" @click.stop>
      <OrderActions @action="emit('action', $event)" />
    </td>
  </tr>
</template>
