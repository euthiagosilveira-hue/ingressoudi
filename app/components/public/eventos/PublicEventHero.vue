<script setup lang="ts">
import { computed, ref } from 'vue'
import { CalendarDaysIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import PublicEventStatusBadge from '~/components/public/eventos/PublicEventStatusBadge.vue'
import { formatData, formatHora } from '~/utils/format'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()

const imagemOk = ref(true)

const mostrarImagem = computed(() => !!props.evento.imagemUrl && imagemOk.value)

const iniciais = computed(() =>
  props.evento.nome
    .split(' ')
    .filter(Boolean)
    .map((palavra) => palavra.charAt(0))
    .slice(0, 2)
    .join('')
    .toUpperCase()
)
</script>

<template>
  <section class="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900">
    <div
      class="relative aspect-[16/9] w-full overflow-hidden bg-gradient-to-br from-zinc-800 via-zinc-900 to-black"
    >
      <img
        v-if="mostrarImagem"
        :src="props.evento.imagemUrl || ''"
        :alt="props.evento.nome"
        class="h-full w-full object-cover"
        @error="imagemOk = false"
      />
      <div v-else class="flex h-full w-full flex-col items-center justify-center gap-3">
        <CalendarDaysIcon class="h-12 w-12 text-amber-400/80" />
        <span class="text-2xl font-bold tracking-[0.2em] text-zinc-200">{{ iniciais }}</span>
      </div>

      <div
        class="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-black/30"
      ></div>

      <div class="absolute left-4 top-4 sm:left-6 sm:top-6">
        <PublicEventStatusBadge :status="props.evento.status" />
      </div>
    </div>

    <div class="space-y-3 p-5 sm:p-7">
      <h1 class="text-3xl font-bold leading-tight text-white sm:text-4xl lg:text-5xl">
        {{ props.evento.nome }}
      </h1>

      <div class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-zinc-300 sm:text-base">
        <span class="inline-flex items-center gap-2">
          <CalendarDaysIcon class="h-5 w-5 shrink-0 text-amber-400" />
          {{ formatData(props.evento.inicioEm) }}
          <span class="text-zinc-500">•</span>
          {{ formatHora(props.evento.inicioEm) }}
        </span>
        <span class="inline-flex items-center gap-2">
          <MapPinIcon class="h-5 w-5 shrink-0 text-amber-400" />
          {{ props.evento.local }}
        </span>
      </div>
    </div>
  </section>
</template>
