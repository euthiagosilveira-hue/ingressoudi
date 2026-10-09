<script setup lang="ts">
import { computed } from 'vue'

import PublicEventUnavailable from '~/components/public/eventos/PublicEventUnavailable.vue'
import type { PublicEventDetail, PublicVendaSituacao } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()

const situacaoBloqueada = computed<Exclude<PublicVendaSituacao, 'DISPONIVEL'> | null>(() =>
  props.evento.situacaoVenda === 'DISPONIVEL' ? null : props.evento.situacaoVenda
)
</script>

<template>
  <section class="mx-auto max-w-2xl px-4 py-16 sm:py-24">
    <h1 class="text-center text-2xl font-bold text-white">Checkout indisponível</h1>
    <p class="mt-2 text-center text-sm text-zinc-400">{{ props.evento.nome }}</p>

    <div class="mt-8">
      <PublicEventUnavailable v-if="situacaoBloqueada" :situacao="situacaoBloqueada" />

      <div
        v-else
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-4 text-red-200"
        role="status"
      >
        <p class="text-sm font-bold uppercase tracking-wide">Venda indisponível</p>
        <p class="mt-1 text-sm opacity-90">
          Não foi possível carregar as informações de venda deste evento.
        </p>
      </div>
    </div>

    <div class="mt-8 flex justify-center">
      <NuxtLink
        :to="`/eventos/${props.evento.slug}`"
        class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-8 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        Voltar ao evento
      </NuxtLink>
    </div>
  </section>
</template>
