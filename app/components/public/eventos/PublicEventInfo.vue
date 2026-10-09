<script setup lang="ts">
import { CalendarDaysIcon, ClockIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import { formatData, formatHora } from '~/utils/format'
import { descreverSituacaoVenda } from '~/utils/publicEvento'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()
</script>

<template>
  <section class="rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-7">
    <h2 class="text-lg font-semibold text-white">Informações</h2>

    <dl class="mt-4 space-y-4 text-sm sm:text-base">
      <div class="flex items-start gap-3">
        <CalendarDaysIcon class="mt-0.5 h-5 w-5 shrink-0 text-amber-400" />
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Data</dt>
          <dd class="text-zinc-200">{{ formatData(props.evento.inicioEm) }}</dd>
        </div>
      </div>

      <div class="flex items-start gap-3">
        <ClockIcon class="mt-0.5 h-5 w-5 shrink-0 text-amber-400" />
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Horário</dt>
          <dd class="text-zinc-200">{{ formatHora(props.evento.inicioEm) }}</dd>
        </div>
      </div>

      <div class="flex items-start gap-3">
        <MapPinIcon class="mt-0.5 h-5 w-5 shrink-0 text-amber-400" />
        <div>
          <dt class="text-xs uppercase tracking-wide text-zinc-500">Local</dt>
          <dd class="text-zinc-200">{{ props.evento.local }}</dd>
          <dd class="text-sm text-zinc-500">{{ props.evento.endereco }}</dd>
        </div>
      </div>
    </dl>

    <p class="mt-5 border-t border-zinc-800 pt-4 text-xs text-zinc-500">
      Situação: <span class="text-zinc-300">{{ descreverSituacaoVenda(props.evento.situacaoVenda) }}</span>
    </p>
  </section>
</template>
