<script setup lang="ts">
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

import OrderStatusBadge from '~/components/pedidos/OrderStatusBadge.vue'
import { formatDataHoraCompleta, formatMoeda, formatNumero } from '~/utils/format'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <NuxtLink
      to="/pedidos"
      class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para pedidos
    </NuxtLink>

    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-3">
          <h1 class="text-2xl font-bold text-white">Pedido {{ props.pedido.codigo }}</h1>
          <OrderStatusBadge :status="props.pedido.status" />
        </div>

        <p class="mt-1 text-sm text-zinc-400">
          Criado em {{ formatDataHoraCompleta(props.pedido.criadoEm) }}
        </p>

        <div class="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-zinc-400">
          <span>
            <span class="text-zinc-500">Evento:</span> {{ props.pedido.eventoNome }}
          </span>
          <span>
            <span class="text-zinc-500">Comprador:</span> {{ props.pedido.compradorNome }}
          </span>
          <span>
            <span class="text-zinc-500">Qtd.:</span>
            {{ formatNumero(props.pedido.quantidade) }}
          </span>
          <span>
            <span class="text-zinc-500">Total:</span>
            <span class="font-semibold text-amber-400">
              {{ formatMoeda(props.pedido.valorTotal) }}
            </span>
          </span>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <slot name="actions" />
      </div>
    </div>
  </div>
</template>
