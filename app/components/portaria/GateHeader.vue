<script setup lang="ts">
import type { EventListItem } from '~/types/evento'
import type { UltimaEntradaGate } from '~/types/gate'

const props = withDefaults(
  defineProps<{
    evento?: EventListItem | null
    totalEntradas?: number
    ultima?: UltimaEntradaGate | null
  }>(),
  { evento: null, totalEntradas: 0, ultima: null }
)
</script>

<template>
  <header class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
    <div class="min-w-0">
      <h1 class="text-2xl font-bold text-white">Portaria</h1>
      <p class="mt-1 text-sm text-zinc-400">
        Valide ingressos e registre entradas do evento.
      </p>
    </div>

    <div class="flex min-w-0 flex-col gap-2 sm:items-end">
      <div class="flex flex-wrap items-center gap-3">
        <span
          v-if="props.evento"
          class="inline-flex items-center gap-2 rounded-full border border-green-500/30 bg-green-500/10 px-3 py-1 text-xs font-semibold text-green-300"
        >
          <span class="h-2 w-2 rounded-full bg-green-400"></span>
          Portaria ativa
        </span>
        <span v-if="props.evento" class="text-xs text-zinc-400">
          Entradas nesta sessão:
          <span class="font-semibold text-zinc-200">{{ props.totalEntradas }}</span>
        </span>
      </div>

      <div
        v-if="props.ultima"
        class="max-w-full rounded-xl border border-zinc-800 bg-zinc-950/60 px-3 py-2 text-xs"
        aria-live="polite"
      >
        <p class="text-[10px] uppercase tracking-wide text-zinc-500">Última entrada</p>
        <p class="truncate font-semibold text-zinc-100">{{ props.ultima.nome }}</p>
        <p class="text-zinc-400">
          {{ props.ultima.tipo
          }}<template v-if="props.ultima.codigo"> {{ props.ultima.codigo }}</template> •
          {{ props.ultima.horario }}
        </p>
      </div>
    </div>
  </header>
</template>
