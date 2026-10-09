<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import OrderPriceTypeBadge from '~/components/pedidos/OrderPriceTypeBadge.vue'
import OrderStatusBadge from '~/components/pedidos/OrderStatusBadge.vue'
import { formatMoeda } from '~/utils/format'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Resumo do pedido
    </h2>

    <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <div>
        <dt class="text-xs text-zinc-500">Código</dt>
        <dd class="text-sm font-semibold text-white">{{ props.pedido.codigo }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Status</dt>
        <dd class="mt-1"><OrderStatusBadge :status="props.pedido.status" /></dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Tipo de preço</dt>
        <dd class="mt-1"><OrderPriceTypeBadge :tipo="props.pedido.tipoPreco" /></dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Quantidade</dt>
        <dd class="text-sm text-zinc-200">{{ props.pedido.quantidade }} ingressos</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Valor unitário</dt>
        <dd class="text-sm text-zinc-200">{{ formatMoeda(props.pedido.valorUnitario) }}</dd>
      </div>
      <div>
        <dt class="text-xs text-zinc-500">Valor total</dt>
        <dd class="text-sm font-semibold text-amber-400">
          {{ formatMoeda(props.pedido.valorTotal) }}
        </dd>
      </div>
    </dl>

    <div class="border-t border-zinc-800 pt-4">
      <template v-if="props.pedido.tipoPreco === 'LOTE'">
        <p class="text-xs text-zinc-500">Lote</p>
        <p class="text-sm text-zinc-200">{{ props.pedido.loteNome ?? 'Lote não informado' }}</p>
      </template>

      <template v-else>
        <p class="text-sm font-medium text-zinc-200">Venda avulsa</p>
        <p v-if="props.pedido.motivoValorAvulso" class="mt-1 text-xs text-zinc-500">
          Motivo: {{ props.pedido.motivoValorAvulso }}
        </p>
        <p v-if="props.pedido.autorizadoPorNome" class="mt-1 text-xs text-zinc-500">
          Autorizado por: {{ props.pedido.autorizadoPorNome }}
        </p>
      </template>
    </div>
  </BaseCard>
</template>
