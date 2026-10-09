<script setup lang="ts">
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

import TicketStatusBadge from '~/components/ingressos/TicketStatusBadge.vue'
import { formatMoeda } from '~/utils/format'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <NuxtLink
      to="/ingressos"
      class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para ingressos
    </NuxtLink>

    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-3">
          <h1 class="break-all text-2xl font-bold text-white">
            Ingresso {{ props.ingresso.codigo }}
          </h1>
          <TicketStatusBadge :status="props.ingresso.status" />
        </div>

        <p class="mt-1 text-sm text-zinc-400">{{ props.ingresso.participanteNome }}</p>

        <div class="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-zinc-400">
          <span>
            <span class="text-zinc-500">Evento:</span> {{ props.ingresso.eventoNome }}
          </span>
          <span>
            <span class="text-zinc-500">Pedido:</span>
            <NuxtLink
              :to="`/pedidos/${props.ingresso.pedidoId}`"
              class="font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
            >
              {{ props.ingresso.pedidoCodigo }}
            </NuxtLink>
          </span>
          <span>
            <span class="text-zinc-500">Lote:</span>
            {{ props.ingresso.loteNome ?? 'Venda avulsa' }}
          </span>
          <span>
            <span class="text-zinc-500">Valor:</span>
            <span class="font-semibold text-amber-400">
              {{ formatMoeda(props.ingresso.valorUnitario) }}
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
