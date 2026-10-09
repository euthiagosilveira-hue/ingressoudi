<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import TicketUsageInfo from '~/components/ingressos/TicketUsageInfo.vue'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()

const estado = computed<{ titulo: string; descricao: string | null }>(() => {
  if (props.ingresso.status === 'UTILIZADO') {
    return { titulo: 'Entrada registrada', descricao: null }
  }
  if (props.ingresso.status === 'RESERVADO') {
    return {
      titulo: 'Aguardando confirmação do pagamento',
      descricao: 'O ingresso será liberado após a confirmação.'
    }
  }
  if (props.ingresso.status === 'EXPIRADO') {
    return {
      titulo: 'Ingresso expirado',
      descricao: 'Este ingresso expirou junto com a reserva.'
    }
  }
  if (props.ingresso.status === 'CANCELADO') {
    return {
      titulo: 'Ingresso cancelado',
      descricao: 'Este ingresso foi cancelado e não pode ser utilizado.'
    }
  }
  return { titulo: 'Ainda não utilizado', descricao: 'Este ingresso está apto para entrada.' }
})

const utilizado = computed(() => props.ingresso.status === 'UTILIZADO')
</script>

<template>
  <BaseCard id="ticket-usage" class="space-y-3">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Utilização
    </h2>

    <p class="text-sm font-semibold text-zinc-100">{{ estado.titulo }}</p>
    <p v-if="estado.descricao" class="text-xs text-zinc-500">{{ estado.descricao }}</p>

    <div v-if="utilizado" class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
      <TicketUsageInfo :ingresso="props.ingresso" />
    </div>
  </BaseCard>
</template>
