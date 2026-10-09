<script setup lang="ts">
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import { formatDataHora } from '~/utils/format'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()

function verEvento() {
  if (!props.pedido.eventoId) {
    toast.info('Evento não disponível.')
    return
  }
  navigateTo(`/eventos/${props.pedido.eventoId}/lotes`)
}
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Evento</h2>

    <dl class="space-y-3">
      <div>
        <dt class="text-xs text-zinc-500">Nome</dt>
        <dd class="text-sm text-zinc-200">{{ props.pedido.eventoNome }}</dd>
      </div>
      <div v-if="props.pedido.eventoInicioEm">
        <dt class="text-xs text-zinc-500">Data e hora</dt>
        <dd class="text-sm text-zinc-200">{{ formatDataHora(props.pedido.eventoInicioEm) }}</dd>
      </div>
      <div v-if="props.pedido.eventoLocal">
        <dt class="text-xs text-zinc-500">Local</dt>
        <dd class="text-sm text-zinc-200">{{ props.pedido.eventoLocal }}</dd>
      </div>
      <div v-if="props.pedido.loteNome">
        <dt class="text-xs text-zinc-500">Lote</dt>
        <dd class="text-sm text-zinc-200">{{ props.pedido.loteNome }}</dd>
      </div>
    </dl>

    <AppButton variant="outline" size="sm" @click="verEvento">Ver evento</AppButton>
  </BaseCard>
</template>
