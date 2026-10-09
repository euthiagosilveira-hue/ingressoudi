<script setup lang="ts">
import { CalendarDaysIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import { formatData, formatHora, formatMoeda } from '~/utils/format'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()
</script>

<template>
  <section class="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900">
    <div v-if="props.evento.imagemUrl" class="aspect-video w-full bg-zinc-950">
      <img
        :src="props.evento.imagemUrl"
        :alt="props.evento.nome"
        class="h-full w-full object-cover"
      />
    </div>

    <div class="space-y-2 p-4">
      <h3 class="text-base font-semibold text-white">{{ props.evento.nome }}</h3>
      <p class="flex items-center gap-2 text-xs text-zinc-400">
        <CalendarDaysIcon class="h-4 w-4 shrink-0 text-amber-400" />
        {{ formatData(props.evento.inicioEm) }} • {{ formatHora(props.evento.inicioEm) }}
      </p>
      <p class="flex items-center gap-2 text-xs text-zinc-500">
        <MapPinIcon class="h-4 w-4 shrink-0" />
        {{ props.evento.local }}
      </p>

      <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-3 text-sm">
        <span class="text-zinc-400">{{ props.evento.loteNome ?? 'Lote' }}</span>
        <span class="font-semibold text-amber-400">
          {{ props.evento.preco !== null ? formatMoeda(props.evento.preco) : '—' }}
        </span>
      </div>
    </div>
  </section>
</template>
