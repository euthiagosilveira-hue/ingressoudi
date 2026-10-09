<script setup lang="ts">
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
  <tr class="border-t border-zinc-800 transition-colors duration-150 hover:bg-zinc-800/40">
    <td class="px-4 py-3">
      <p class="break-all text-sm font-semibold text-white">{{ props.pagamento.transactionId }}</p>
      <div class="mt-1"><PaymentProviderBadge :provider="props.pagamento.provider" /></div>
    </td>

    <td class="px-4 py-3">
      <NuxtLink
        :to="`/pedidos/${props.pagamento.pedidoId}`"
        class="text-sm font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        {{ props.pagamento.pedidoCodigo }}
      </NuxtLink>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-200">{{ props.pagamento.compradorNome }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ props.pagamento.eventoNome }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm font-semibold text-amber-400">{{ formatMoeda(props.pagamento.valor) }}</p>
      <p v-if="props.pagamento.valorReembolsado > 0" class="text-xs text-violet-300">
        Reembolsado: {{ formatMoeda(props.pagamento.valorReembolsado) }}
      </p>
    </td>

    <td class="px-4 py-3">
      <PaymentStatusBadge :status="props.pagamento.status" />
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ formatDataNumerica(props.pagamento.criadoEm) }}</p>
      <p class="text-xs text-zinc-500">{{ formatHora(props.pagamento.criadoEm) }}</p>
    </td>

    <td class="px-4 py-3">
      <PaymentActions :status="props.pagamento.status" @action="repassar" />
    </td>
  </tr>
</template>
