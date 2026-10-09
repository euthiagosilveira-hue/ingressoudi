<script setup lang="ts">
import TicketActions from '~/components/ingressos/TicketActions.vue'
import TicketStatusBadge from '~/components/ingressos/TicketStatusBadge.vue'
import TicketUsageInfo from '~/components/ingressos/TicketUsageInfo.vue'
import { formatMoeda } from '~/utils/format'
import type { TicketListItem } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketListItem
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; eventoId: string; action: string }]
}>()

function repassar(action: string) {
  emit('action', {
    id: props.ingresso.id,
    pedidoId: props.ingresso.pedidoId,
    eventoId: props.ingresso.eventoId,
    action
  })
}
</script>

<template>
  <tr class="border-t border-zinc-800 transition-colors duration-150 hover:bg-zinc-800/40">
    <td class="px-4 py-3">
      <p class="text-sm font-semibold text-white">{{ props.ingresso.codigo }}</p>
      <p class="text-xs text-zinc-500">{{ props.ingresso.loteNome ?? 'Venda avulsa' }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-200">{{ props.ingresso.participanteNome }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ props.ingresso.eventoNome }}</p>
    </td>

    <td class="px-4 py-3">
      <NuxtLink
        :to="`/pedidos/${props.ingresso.pedidoId}`"
        class="text-sm font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        {{ props.ingresso.pedidoCodigo }}
      </NuxtLink>
    </td>

    <td class="px-4 py-3">
      <span class="text-sm text-zinc-200">{{ formatMoeda(props.ingresso.valorUnitario) }}</span>
    </td>

    <td class="px-4 py-3">
      <TicketStatusBadge :status="props.ingresso.status" />
    </td>

    <td class="px-4 py-3">
      <TicketUsageInfo :ingresso="props.ingresso" />
    </td>

    <td class="px-4 py-3">
      <TicketActions @action="repassar" />
    </td>
  </tr>
</template>
