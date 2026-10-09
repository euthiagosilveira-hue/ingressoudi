<script setup lang="ts">
import { CheckCircleIcon } from '@heroicons/vue/24/outline'

import { formatHora, formatMoeda } from '~/utils/format'
import type { CheckoutReservation } from '~/types/checkout'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = defineProps<{
  reserva: CheckoutReservation
  evento: PublicEventDetail
}>()
</script>

<template>
  <section class="space-y-5 rounded-2xl border-2 border-green-500/50 bg-zinc-900 p-5 sm:p-6" role="status">
    <div class="flex items-center gap-4">
      <span
        class="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border border-zinc-700 bg-zinc-950"
      >
        <CheckCircleIcon class="h-7 w-7 text-green-300" />
      </span>
      <div>
        <p class="text-lg font-bold uppercase tracking-wide text-green-300">Reserva criada</p>
        <p class="text-sm text-zinc-400">
          Seus ingressos estão reservados por 30 minutos.
        </p>
      </div>
    </div>

    <dl class="space-y-2 rounded-xl border border-zinc-800 bg-zinc-950/60 p-4 text-sm">
      <div class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Código do pedido</dt>
        <dd class="font-semibold text-white">{{ props.reserva.codigoPedido }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Evento</dt>
        <dd class="text-right text-zinc-200">{{ props.evento.nome }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Quantidade</dt>
        <dd class="text-zinc-200">{{ props.reserva.quantidade }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Total</dt>
        <dd class="font-bold text-amber-400">{{ formatMoeda(props.reserva.valorTotal) }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-2">
        <dt class="text-zinc-500">Reserva válida até</dt>
        <dd class="font-semibold text-zinc-100">{{ formatHora(props.reserva.reservaExpiraEm) }}</dd>
      </div>
    </dl>

    <p class="text-sm text-zinc-400">Na próxima etapa você fará o pagamento via Pix.</p>

    <NuxtLink
      v-if="props.reserva.checkoutToken"
      :to="`/eventos/${props.evento.slug}/comprar/pagamento?token=${props.reserva.checkoutToken}`"
      class="flex w-full items-center justify-center rounded-xl bg-amber-400 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60"
    >
      Continuar para pagamento
    </NuxtLink>

    <button
      v-else
      type="button"
      disabled
      class="flex w-full cursor-not-allowed items-center justify-center rounded-xl border border-zinc-700 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-500 opacity-70"
    >
      Pagamento disponível apenas com dados reais
    </button>
  </section>
</template>
