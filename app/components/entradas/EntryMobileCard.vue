<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import EntryActions from '~/components/entradas/EntryActions.vue'
import EntryMethodBadge from '~/components/entradas/EntryMethodBadge.vue'
import EntryStatusBadge from '~/components/entradas/EntryStatusBadge.vue'
import { estadoEntrada } from '~/utils/entradas'
import { formatHora } from '~/utils/format'
import type { EntryListItem } from '~/types/entrada'

const props = defineProps<{
  entrada: EntryListItem
}>()

const emit = defineEmits<{
  action: [{ id: string; ingressoId: string; pedidoId: string; action: string }]
}>()

function repassar(action: string) {
  emit('action', {
    id: props.entrada.id,
    ingressoId: props.entrada.ingressoId,
    pedidoId: props.entrada.pedidoId,
    action
  })
}
</script>

<template>
  <BaseCard class="flex flex-col gap-3" :class="props.entrada.anuladaEm ? 'opacity-70' : ''">
    <div class="flex items-start justify-between gap-3">
      <p class="text-sm font-semibold tabular-nums text-zinc-300">
        {{ formatHora(props.entrada.entradaEm) }}
      </p>
      <EntryStatusBadge :state="estadoEntrada(props.entrada)" />
    </div>

    <div class="min-w-0">
      <p class="truncate text-sm text-zinc-100">{{ props.entrada.participanteNome }}</p>
      <p class="truncate text-xs text-zinc-500">{{ props.entrada.eventoNome }}</p>
    </div>

    <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-zinc-500">
      <NuxtLink
        :to="`/ingressos/${props.entrada.ingressoId}`"
        class="font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        {{ props.entrada.ingressoCodigo }}
      </NuxtLink>
      <EntryMethodBadge :metodo="props.entrada.metodo" />
    </div>

    <p class="text-xs text-zinc-500">Operador: {{ props.entrada.usuarioNome }}</p>

    <div
      v-if="props.entrada.anuladaEm"
      class="rounded-xl border border-red-500/30 bg-red-500/5 p-2.5"
    >
      <p class="text-xs font-semibold text-red-300">Entrada anulada</p>
      <p class="text-[11px] text-zinc-500">Motivo: {{ props.entrada.motivoAnulacao ?? '—' }}</p>
    </div>

    <div class="border-t border-zinc-800 pt-3">
      <EntryActions :state="estadoEntrada(props.entrada)" inline @action="repassar" />
    </div>
  </BaseCard>
</template>
