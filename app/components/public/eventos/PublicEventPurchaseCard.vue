<script setup lang="ts">
import { computed } from 'vue'

import PublicEventAvailability from '~/components/public/eventos/PublicEventAvailability.vue'
import PublicEventUnavailable from '~/components/public/eventos/PublicEventUnavailable.vue'
import { formatMoeda } from '~/utils/format'
import type { PublicEventDetail, PublicVendaSituacao } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()

const situacaoBloqueada = computed<Exclude<PublicVendaSituacao, 'DISPONIVEL'> | null>(() =>
  props.evento.situacaoVenda === 'DISPONIVEL' ? null : props.evento.situacaoVenda
)
</script>

<template>
  <section class="rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6 lg:sticky lg:top-24">
    <template v-if="situacaoBloqueada">
      <PublicEventUnavailable :situacao="situacaoBloqueada" />
    </template>

    <template v-else>
      <p class="text-xs uppercase tracking-wide text-zinc-500">Lote atual</p>
      <p class="text-sm font-semibold text-white">{{ props.evento.loteNome ?? 'Lote' }}</p>

      <div class="mt-4">
        <p class="text-3xl font-bold text-amber-400">
          {{ formatMoeda(props.evento.preco ?? 0) }}
        </p>
        <p class="text-xs text-zinc-500">por ingresso</p>
      </div>

      <div class="mt-3">
        <PublicEventAvailability :disponiveis="props.evento.disponiveis" />
      </div>

      <NuxtLink
        :to="`/eventos/${props.evento.slug}/comprar`"
        class="mt-6 flex w-full items-center justify-center rounded-xl bg-amber-400 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60"
      >
        Comprar ingresso
      </NuxtLink>
    </template>
  </section>
</template>
