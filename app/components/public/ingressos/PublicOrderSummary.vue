<script setup lang="ts">
import { formatDataHoraCompleta } from '~/utils/format'
import type { PublicOrderTickets } from '~/types/publicIngressos'

const props = defineProps<{
  tickets: PublicOrderTickets
}>()
</script>

<template>
  <dl class="space-y-2 rounded-xl border border-zinc-800 bg-zinc-950/60 p-4 text-sm">
    <div class="flex items-start justify-between gap-3">
      <dt class="text-zinc-500">Evento</dt>
      <dd class="text-right text-zinc-200">{{ props.tickets.eventoNome }}</dd>
    </div>
    <div class="flex items-center justify-between gap-3">
      <dt class="text-zinc-500">Pedido</dt>
      <dd class="font-semibold text-white">{{ props.tickets.codigoPedido }}</dd>
    </div>
    <div class="flex items-start justify-between gap-3">
      <dt class="text-zinc-500">Data</dt>
      <dd class="text-right text-zinc-200">{{ formatDataHoraCompleta(props.tickets.eventoInicioEm) }}</dd>
    </div>
    <div class="flex items-start justify-between gap-3">
      <dt class="text-zinc-500">Local</dt>
      <dd class="text-right text-zinc-200">
        {{ props.tickets.eventoLocal }}
        <span v-if="props.tickets.eventoEndereco" class="block text-xs text-zinc-500">
          {{ props.tickets.eventoEndereco }}
        </span>
      </dd>
    </div>
    <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-2">
      <dt class="font-medium text-zinc-300">Ingressos</dt>
      <dd class="font-semibold text-zinc-200">{{ props.tickets.ingressos.length }}</dd>
    </div>
  </dl>
</template>
