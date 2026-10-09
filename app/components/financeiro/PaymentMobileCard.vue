<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import PaymentActions from '~/components/financeiro/PaymentActions.vue'
import PaymentProviderBadge from '~/components/financeiro/PaymentProviderBadge.vue'
import PaymentStatusBadge from '~/components/financeiro/PaymentStatusBadge.vue'
import { formatDataNumerica, formatHora, formatMoeda } from '~/utils/format'
import type { PaymentListItem } from '~/types/pagamento'

const props = defineProps<{
  pagamento: PaymentListItem
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; action: string }]
}>()

function repassar(action: string) {
  emit('action', { id: props.pagamento.id, pedidoId: props.pagamento.pedidoId, action })
}
</script>

<template>
  <BaseCard class="flex flex-col gap-3">
    <div class="flex items-start justify-between gap-3">
      <NuxtLink
        :to="`/pedidos/${props.pagamento.pedidoId}`"
        class="truncate text-sm font-semibold text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        {{ props.pagamento.pedidoCodigo }}
      </NuxtLink>
      <PaymentStatusBadge :status="props.pagamento.status" />
    </div>

    <div class="min-w-0">
      <p class="truncate text-sm text-zinc-100">{{ props.pagamento.compradorNome }}</p>
      <p class="truncate text-xs text-zinc-500">{{ props.pagamento.eventoNome }}</p>
    </div>

    <p class="text-lg font-bold text-amber-400">{{ formatMoeda(props.pagamento.valor) }}</p>
    <p v-if="props.pagamento.valorReembolsado > 0" class="text-xs text-violet-300">
      Reembolsado: {{ formatMoeda(props.pagamento.valorReembolsado) }}
    </p>

    <div class="flex flex-wrap items-center gap-x-3 gap-y-2 text-xs text-zinc-500">
      <PaymentProviderBadge :provider="props.pagamento.provider" />
      <span>{{ formatDataNumerica(props.pagamento.criadoEm) }} • {{ formatHora(props.pagamento.criadoEm) }}</span>
    </div>

    <div class="border-t border-zinc-800 pt-3">
      <PaymentActions :status="props.pagamento.status" inline @action="repassar" />
    </div>
  </BaseCard>
</template>
