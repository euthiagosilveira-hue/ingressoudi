<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import OrderPriceTypeBadge from '~/components/pedidos/OrderPriceTypeBadge.vue'
import TicketStatusBadge from '~/components/ingressos/TicketStatusBadge.vue'
import { formatDataHoraCompleta, formatMoeda } from '~/utils/format'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Dados do ingresso
    </h2>

    <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div>
        <dt class="text-xs text-zinc-500">Código</dt>
        <dd class="break-all text-sm font-semibold text-white">{{ props.ingresso.codigo }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Status</dt>
        <dd class="mt-1"><TicketStatusBadge :status="props.ingresso.status" /></dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Pedido</dt>
        <dd class="mt-0.5">
          <NuxtLink
            :to="`/pedidos/${props.ingresso.pedidoId}`"
            class="text-sm font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
          >
            {{ props.ingresso.pedidoCodigo }}
          </NuxtLink>
        </dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Tipo de preço</dt>
        <dd class="mt-1"><OrderPriceTypeBadge :tipo="props.ingresso.tipoPreco" /></dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Lote</dt>
        <dd class="text-sm text-zinc-200">{{ props.ingresso.loteNome ?? 'Venda avulsa' }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Valor unitário</dt>
        <dd class="text-sm font-semibold text-amber-400">
          {{ formatMoeda(props.ingresso.valorUnitario) }}
        </dd>
      </div>
      <div class="sm:col-span-2">
        <dt class="text-xs text-zinc-500">Emitido em</dt>
        <dd class="text-sm text-zinc-200">{{ formatDataHoraCompleta(props.ingresso.criadoEm) }}</dd>
      </div>
    </dl>
  </BaseCard>
</template>
