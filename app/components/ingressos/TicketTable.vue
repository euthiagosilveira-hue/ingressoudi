<script setup lang="ts">
import TicketTableRow from '~/components/ingressos/TicketTableRow.vue'
import type { TicketListItem } from '~/types/ingresso'

const props = defineProps<{
  ingressos: TicketListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; eventoId: string; action: string }]
}>()
</script>

<template>
  <div class="overflow-x-auto rounded-2xl border border-zinc-800 bg-zinc-900">
    <table class="w-full min-w-[860px] border-collapse text-left">
      <thead>
        <tr class="text-[11px] uppercase tracking-wide text-zinc-500">
          <th scope="col" class="px-4 py-3 font-medium">Ingresso</th>
          <th scope="col" class="px-4 py-3 font-medium">Participante</th>
          <th scope="col" class="px-4 py-3 font-medium">Evento</th>
          <th scope="col" class="px-4 py-3 font-medium">Pedido</th>
          <th scope="col" class="px-4 py-3 font-medium">Valor</th>
          <th scope="col" class="px-4 py-3 font-medium">Status</th>
          <th scope="col" class="px-4 py-3 font-medium">Utilização</th>
          <th scope="col" class="px-4 py-3 text-right font-medium">Ações</th>
        </tr>
      </thead>
      <tbody>
        <TicketTableRow
          v-for="ingresso in props.ingressos"
          :key="ingresso.id"
          :ingresso="ingresso"
          @action="emit('action', $event)"
        />
      </tbody>
    </table>
  </div>
</template>
