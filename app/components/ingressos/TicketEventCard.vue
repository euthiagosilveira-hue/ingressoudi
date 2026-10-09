<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import { formatDataHora } from '~/utils/format'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()

function verEvento() {
  navigateTo('/eventos')
}

function verLotes() {
  navigateTo(`/eventos/${props.ingresso.eventoId}/lotes`)
}
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Evento</h2>

    <dl class="space-y-3">
      <div>
        <dt class="text-xs text-zinc-500">Nome</dt>
        <dd class="text-sm text-zinc-200">{{ props.ingresso.eventoNome }}</dd>
      </div>
      <div v-if="props.ingresso.eventoInicioEm">
        <dt class="text-xs text-zinc-500">Data e hora</dt>
        <dd class="text-sm text-zinc-200">{{ formatDataHora(props.ingresso.eventoInicioEm) }}</dd>
      </div>
      <div v-if="props.ingresso.eventoLocal">
        <dt class="text-xs text-zinc-500">Local</dt>
        <dd class="text-sm text-zinc-200">{{ props.ingresso.eventoLocal }}</dd>
      </div>
      <div v-if="props.ingresso.loteNome">
        <dt class="text-xs text-zinc-500">Lote</dt>
        <dd class="text-sm text-zinc-200">{{ props.ingresso.loteNome }}</dd>
      </div>
    </dl>

    <div class="flex flex-wrap items-center gap-2">
      <AppButton variant="outline" size="sm" @click="verLotes">Ver lotes</AppButton>
      <AppButton variant="ghost" size="sm" @click="verEvento">Ver evento</AppButton>
    </div>
  </BaseCard>
</template>
