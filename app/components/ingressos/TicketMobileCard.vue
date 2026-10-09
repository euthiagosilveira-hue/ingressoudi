<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
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

const reservado = computed(() => props.ingresso.status === 'RESERVADO')

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
  <BaseCard class="flex flex-col gap-3">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <p class="truncate text-sm font-semibold text-white">{{ props.ingresso.codigo }}</p>
        <p class="mt-1 truncate text-sm text-zinc-200">{{ props.ingresso.participanteNome }}</p>
        <p class="truncate text-xs text-zinc-500">{{ props.ingresso.eventoNome }}</p>
      </div>
      <TicketStatusBadge :status="props.ingresso.status" />
    </div>

    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-zinc-800 pt-3 text-xs text-zinc-500">
      <NuxtLink
        :to="`/pedidos/${props.ingresso.pedidoId}`"
        class="font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        Pedido {{ props.ingresso.pedidoCodigo }}
      </NuxtLink>
      <span class="truncate">{{ props.ingresso.loteNome ?? 'Venda avulsa' }}</span>
    </div>

    <div class="flex items-end justify-between gap-3">
      <div class="space-y-1">
        <p class="text-lg font-bold text-amber-400">
          {{ formatMoeda(props.ingresso.valorUnitario) }}
        </p>
        <TicketUsageInfo :ingresso="props.ingresso" />
        <p v-if="reservado" class="text-xs text-amber-300/80">Aguardando pagamento</p>
      </div>
      <div class="border-t border-transparent pt-0">
        <TicketActions inline @action="repassar" />
      </div>
    </div>
  </BaseCard>
</template>
