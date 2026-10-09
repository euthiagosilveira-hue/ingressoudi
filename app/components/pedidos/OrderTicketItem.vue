<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import TicketStatusBadge from '~/components/ingressos/TicketStatusBadge.vue'
import { formatDataHoraCompleta, formatMoeda } from '~/utils/format'
import type { OrderTicket } from '~/types/ingresso'

const props = defineProps<{
  ingresso: OrderTicket
}>()

const emit = defineEmits<{
  visualizar: []
}>()
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-xl border border-zinc-800 bg-zinc-950/60 p-3 sm:flex-row sm:items-center sm:justify-between"
  >
    <div class="min-w-0">
      <p class="truncate text-sm font-semibold text-white">{{ props.ingresso.codigo }}</p>
      <p class="truncate text-xs text-zinc-400">{{ props.ingresso.participanteNome }}</p>
      <p
        v-if="props.ingresso.status === 'UTILIZADO' && props.ingresso.utilizadoEm"
        class="mt-0.5 text-[11px] text-zinc-500"
      >
        Utilizado em {{ formatDataHoraCompleta(props.ingresso.utilizadoEm) }}
      </p>
    </div>

    <div class="flex flex-wrap items-center gap-3 sm:justify-end">
      <span class="text-sm text-zinc-200">{{ formatMoeda(props.ingresso.valorUnitario) }}</span>
      <TicketStatusBadge :status="props.ingresso.status" />
      <AppButton variant="ghost" size="sm" @click="emit('visualizar')">
        Visualizar ingresso
      </AppButton>
    </div>
  </div>
</template>
