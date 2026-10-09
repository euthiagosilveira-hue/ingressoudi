<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import OrderPaymentStatusBadge from '~/components/pedidos/OrderPaymentStatusBadge.vue'
import { formatDataHoraCompleta, formatMoeda } from '~/utils/format'
import { rotuloProvider } from '~/utils/pagamentos'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()

const pagamento = computed(() => props.pedido.pagamento)
const reservaAtiva = computed(
  () => pagamento.value?.status === 'PENDENTE' && !!pagamento.value?.expiraEm
)
const provedorRotulo = computed(() =>
  pagamento.value ? rotuloProvider(pagamento.value.provider) : ''
)
</script>

<template>
  <BaseCard id="order-payment" class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Pagamento</h2>

    <p v-if="!pagamento" class="text-sm text-zinc-500">
      Sem pagamento registrado para este pedido.
    </p>

    <template v-else>
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm text-zinc-500">Status</span>
        <OrderPaymentStatusBadge :status="pagamento.status" />
      </div>

      <div
        v-if="reservaAtiva"
        class="rounded-xl border border-amber-400/30 bg-amber-400/5 p-3"
      >
        <p class="text-sm font-semibold text-amber-300">Reserva ativa</p>
        <p class="mt-0.5 text-xs text-amber-200/80">
          Expira em {{ formatDataHoraCompleta(pagamento.expiraEm ?? '') }}
        </p>
        <p class="mt-1 text-xs text-zinc-400">Pagamento esperado: Pendente.</p>
      </div>

      <dl class="space-y-3">
        <div class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Provedor</dt>
          <dd class="text-sm text-zinc-200">{{ provedorRotulo }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Valor</dt>
          <dd class="text-sm text-zinc-200">{{ formatMoeda(pagamento.valor) }}</dd>
        </div>
        <div v-if="pagamento.expiraEm" class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Expira em</dt>
          <dd class="text-sm text-zinc-200">{{ formatDataHoraCompleta(pagamento.expiraEm) }}</dd>
        </div>
        <div v-if="pagamento.confirmadoEm" class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Confirmado em</dt>
          <dd class="text-sm text-zinc-200">{{ formatDataHoraCompleta(pagamento.confirmadoEm) }}</dd>
        </div>
        <div v-if="pagamento.canceladoEm" class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Cancelado em</dt>
          <dd class="text-sm text-zinc-200">{{ formatDataHoraCompleta(pagamento.canceladoEm) }}</dd>
        </div>
        <div v-if="pagamento.reembolsadoEm" class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Reembolsado em</dt>
          <dd class="text-sm text-zinc-200">{{ formatDataHoraCompleta(pagamento.reembolsadoEm) }}</dd>
        </div>
        <div v-if="pagamento.valorReembolsado > 0" class="flex items-center justify-between gap-3">
          <dt class="text-sm text-zinc-500">Valor reembolsado</dt>
          <dd class="text-sm text-zinc-200">{{ formatMoeda(pagamento.valorReembolsado) }}</dd>
        </div>
      </dl>

      <div class="space-y-1 border-t border-zinc-800 pt-3">
        <p v-if="pagamento.transactionId" class="break-all text-[11px] text-zinc-500">
          ID da transação: <span class="text-zinc-400">{{ pagamento.transactionId }}</span>
        </p>
        <p v-if="pagamento.chargeId" class="break-all text-[11px] text-zinc-500">
          ID da cobrança: <span class="text-zinc-400">{{ pagamento.chargeId }}</span>
        </p>
        <p class="break-all text-[11px] text-zinc-500">
          Referência externa: <span class="text-zinc-400">{{ pagamento.externalReference }}</span>
        </p>
      </div>
    </template>
  </BaseCard>
</template>
