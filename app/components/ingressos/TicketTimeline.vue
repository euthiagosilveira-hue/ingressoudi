<script setup lang="ts">
import { computed } from 'vue'
import type { Component } from 'vue'
import {
  ArrowRightOnRectangleIcon,
  ArrowUturnLeftIcon,
  CheckCircleIcon,
  ClockIcon,
  InboxArrowDownIcon,
  TicketIcon,
  XCircleIcon
} from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import { formatDataHoraCompleta } from '~/utils/format'
import type { TicketHistoryEvent, TicketHistoryType } from '~/types/ingresso'

const props = defineProps<{
  eventos: TicketHistoryEvent[]
}>()

const icones: Record<TicketHistoryType, Component> = {
  INGRESSO_RESERVADO: TicketIcon,
  PAGAMENTO_CONFIRMADO: CheckCircleIcon,
  INGRESSO_LIBERADO: InboxArrowDownIcon,
  ENTRADA_REGISTRADA: ArrowRightOnRectangleIcon,
  ENTRADA_ANULADA: ArrowUturnLeftIcon,
  INGRESSO_EXPIRADO: ClockIcon,
  INGRESSO_CANCELADO: XCircleIcon
}

const cores: Record<TicketHistoryType, string> = {
  INGRESSO_RESERVADO: 'text-amber-300',
  PAGAMENTO_CONFIRMADO: 'text-green-300',
  INGRESSO_LIBERADO: 'text-green-300',
  ENTRADA_REGISTRADA: 'text-green-300',
  ENTRADA_ANULADA: 'text-red-300',
  INGRESSO_EXPIRADO: 'text-zinc-500',
  INGRESSO_CANCELADO: 'text-red-300'
}

const ordenados = computed(() =>
  [...props.eventos].sort(
    (a, b) => new Date(b.ocorridoEm).getTime() - new Date(a.ocorridoEm).getTime()
  )
)
</script>

<template>
  <BaseCard id="ticket-timeline" class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Histórico</h2>

    <ol>
      <li
        v-for="(evento, indice) in ordenados"
        :key="evento.id"
        class="relative flex gap-3 pb-5 last:pb-0"
      >
        <span
          v-if="indice < ordenados.length - 1"
          class="absolute left-4 top-8 h-[calc(100%-2rem)] w-px bg-zinc-800"
          aria-hidden="true"
        ></span>

        <span
          class="relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900"
          :class="cores[evento.tipo]"
        >
          <component :is="icones[evento.tipo]" class="h-4 w-4" />
        </span>

        <div class="min-w-0 pt-0.5">
          <p class="text-sm font-medium text-zinc-100">{{ evento.titulo }}</p>
          <p v-if="evento.descricao" class="text-xs text-zinc-500">{{ evento.descricao }}</p>
          <p class="mt-0.5 text-[11px] text-zinc-500">
            {{ formatDataHoraCompleta(evento.ocorridoEm) }}
          </p>
        </div>
      </li>
    </ol>
  </BaseCard>
</template>
