<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ExclamationTriangleIcon, TicketIcon } from '@heroicons/vue/24/outline'

import { obterCompartilhamento } from '~/services/public/compartilhamento'
import type { SharedTicket } from '~/types/compartilhamento'
import { formatDataHoraCompleta } from '~/utils/format'

const route = useRoute()
const token = computed(() => String(route.params.token ?? '').trim())

const ticket = ref<SharedTicket | null>(null)
const carregando = ref(true)

onMounted(async () => {
  try {
    ticket.value = await obterCompartilhamento(token.value)
  } catch {
    ticket.value = null
  } finally {
    carregando.value = false
  }
})

const qrUrl = computed(() => `/api/tickets/shared/${encodeURIComponent(token.value)}/qr`)
const podeQr = computed(() => ticket.value?.status === 'VALIDO')

const rotuloStatus = computed(() => {
  switch (ticket.value?.status) {
    case 'VALIDO':
      return 'Válido'
    case 'UTILIZADO':
      return 'Utilizado'
    case 'CANCELADO':
      return 'Cancelado'
    case 'EXPIRADO':
      return 'Expirado'
    default:
      return ticket.value?.status ?? ''
  }
})

const aviso = computed(() => {
  switch (ticket.value?.status) {
    case 'UTILIZADO':
      return 'Ingresso já utilizado'
    case 'CANCELADO':
      return 'Ingresso cancelado'
    case 'EXPIRADO':
      return 'Ingresso expirado'
    default:
      return null
  }
})
</script>

<template>
  <main class="mx-auto w-full max-w-2xl px-4 py-8 sm:px-6 sm:py-12">
    <div v-if="carregando" class="space-y-4">
      <div class="h-8 w-48 animate-pulse rounded bg-zinc-800" />
      <div class="h-80 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>

    <div
      v-else-if="!ticket"
      class="space-y-4 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
    >
      <ExclamationTriangleIcon class="mx-auto h-8 w-8 text-amber-400" />
      <p class="text-base font-semibold text-zinc-200">Ingresso não encontrado</p>
      <p class="text-sm text-zinc-400">Este link é inválido ou expirou.</p>
    </div>

    <article v-else class="space-y-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="text-base font-semibold text-white">{{ ticket.participanteNome }}</p>
          <p class="text-xs text-zinc-500">Ingresso {{ ticket.codigo }}</p>
        </div>
        <span
          class="shrink-0 rounded-full border border-zinc-700 px-3 py-1 text-xs font-semibold text-zinc-300"
        >
          {{ rotuloStatus }}
        </span>
      </div>

      <div class="rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-xs text-zinc-400">
        <p class="font-medium text-zinc-200">{{ ticket.eventoNome }}</p>
        <p v-if="ticket.eventoInicioEm">{{ formatDataHoraCompleta(ticket.eventoInicioEm) }}</p>
        <p v-if="ticket.eventoLocal">{{ ticket.eventoLocal }}</p>
      </div>

      <template v-if="podeQr">
        <div class="mx-auto w-full max-w-xs rounded-2xl bg-white p-4">
          <img :src="qrUrl" alt="QR Code do ingresso" class="mx-auto block h-auto w-full" />
        </div>
        <p class="text-center text-sm text-zinc-400">Apresente este QR Code na entrada.</p>
      </template>

      <p
        v-else
        class="flex items-center justify-center gap-2 rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-center text-sm font-semibold text-zinc-300"
      >
        <TicketIcon class="h-4 w-4 text-zinc-500" />
        {{ aviso ?? 'Ingresso indisponível' }}
      </p>

      <p v-if="ticket.status === 'UTILIZADO' && (ticket.entradaEm || ticket.utilizadoEm)" class="text-center text-xs text-zinc-500">
        Entrada registrada em
        {{ formatDataHoraCompleta(ticket.entradaEm ?? ticket.utilizadoEm ?? '') }}.
      </p>
    </article>
  </main>
</template>
