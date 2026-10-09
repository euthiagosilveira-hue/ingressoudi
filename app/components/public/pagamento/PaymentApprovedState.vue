<script setup lang="ts">
import { CheckCircleIcon } from '@heroicons/vue/24/outline'

import PaymentSummary from '~/components/public/pagamento/PaymentSummary.vue'
import type { CheckoutPublico } from '~/types/checkoutPagamento'

const props = defineProps<{
  checkout: CheckoutPublico
  slug: string
  checkoutToken: string | null
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
        <p class="text-lg font-bold uppercase tracking-wide text-green-300">Pagamento confirmado</p>
        <p class="text-sm text-zinc-400">
          Seu pedido foi confirmado e seus ingressos já estão disponíveis.
        </p>
      </div>
    </div>

    <PaymentSummary :checkout="props.checkout" />

    <NuxtLink
      v-if="props.slug && props.checkoutToken"
      :to="`/eventos/${props.slug}/comprar/ingressos?token=${props.checkoutToken}`"
      class="flex w-full items-center justify-center rounded-xl bg-amber-400 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60"
    >
      Ver meus ingressos
    </NuxtLink>

    <button
      v-else
      type="button"
      disabled
      class="flex w-full cursor-not-allowed items-center justify-center rounded-xl border border-zinc-700 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-500 opacity-70"
    >
      Ver meus ingressos
    </button>
  </section>
</template>
