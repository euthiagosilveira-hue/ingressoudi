<script setup lang="ts">
import EntryActions from '~/components/entradas/EntryActions.vue'
import EntryMethodBadge from '~/components/entradas/EntryMethodBadge.vue'
import EntryStatusBadge from '~/components/entradas/EntryStatusBadge.vue'
import { estadoEntrada } from '~/utils/entradas'
import { formatDataNumerica, formatHora } from '~/utils/format'
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
  <tr
    class="border-t border-zinc-800 transition-colors duration-150 hover:bg-zinc-800/40"
    :class="props.entrada.anuladaEm ? 'opacity-70' : ''"
  >
    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ formatDataNumerica(props.entrada.entradaEm) }}</p>
      <p class="text-xs text-zinc-500">{{ formatHora(props.entrada.entradaEm) }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-200">{{ props.entrada.participanteNome }}</p>
      <p class="text-xs text-zinc-500">{{ props.entrada.pedidoCodigo }}</p>
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ props.entrada.eventoNome }}</p>
    </td>

    <td class="px-4 py-3">
      <NuxtLink
        :to="`/ingressos/${props.entrada.ingressoId}`"
        class="text-sm font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        {{ props.entrada.ingressoCodigo }}
      </NuxtLink>
    </td>

    <td class="px-4 py-3">
      <EntryMethodBadge :metodo="props.entrada.metodo" />
    </td>

    <td class="px-4 py-3">
      <p class="text-sm text-zinc-300">{{ props.entrada.usuarioNome }}</p>
    </td>

    <td class="px-4 py-3">
      <EntryStatusBadge :state="estadoEntrada(props.entrada)" />
      <p v-if="props.entrada.anuladaEm" class="mt-1 text-[11px] text-zinc-500">
        Anulada em {{ formatDataNumerica(props.entrada.anuladaEm) }}
      </p>
    </td>

    <td class="px-4 py-3">
      <EntryActions :state="estadoEntrada(props.entrada)" @action="repassar" />
    </td>
  </tr>
</template>
