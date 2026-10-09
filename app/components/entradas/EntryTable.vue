<script setup lang="ts">
import EntryTableRow from '~/components/entradas/EntryTableRow.vue'
import type { EntryListItem } from '~/types/entrada'

const props = defineProps<{
  entradas: EntryListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; ingressoId: string; pedidoId: string; action: string }]
}>()
</script>

<template>
  <div class="overflow-x-auto rounded-2xl border border-zinc-800 bg-zinc-900">
    <table class="w-full min-w-[900px] border-collapse text-left">
      <thead>
        <tr class="text-[11px] uppercase tracking-wide text-zinc-500">
          <th scope="col" class="px-4 py-3 font-medium">Entrada</th>
          <th scope="col" class="px-4 py-3 font-medium">Participante</th>
          <th scope="col" class="px-4 py-3 font-medium">Evento</th>
          <th scope="col" class="px-4 py-3 font-medium">Ingresso</th>
          <th scope="col" class="px-4 py-3 font-medium">Método</th>
          <th scope="col" class="px-4 py-3 font-medium">Operador</th>
          <th scope="col" class="px-4 py-3 font-medium">Situação</th>
          <th scope="col" class="px-4 py-3 text-right font-medium">Ações</th>
        </tr>
      </thead>
      <tbody>
        <EntryTableRow
          v-for="entrada in props.entradas"
          :key="entrada.id"
          :entrada="entrada"
          @action="emit('action', $event)"
        />
      </tbody>
    </table>
  </div>
</template>
