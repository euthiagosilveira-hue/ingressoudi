<script setup lang="ts">
import { onMounted } from 'vue'

import TicketDetailActions from '~/components/ingressos/TicketDetailActions.vue'
import TicketDetailHeader from '~/components/ingressos/TicketDetailHeader.vue'
import TicketEventCard from '~/components/ingressos/TicketEventCard.vue'
import TicketOverviewCard from '~/components/ingressos/TicketOverviewCard.vue'
import TicketParticipantCard from '~/components/ingressos/TicketParticipantCard.vue'
import TicketQrCard from '~/components/ingressos/TicketQrCard.vue'
import TicketTimeline from '~/components/ingressos/TicketTimeline.vue'
import TicketUsageCard from '~/components/ingressos/TicketUsageCard.vue'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()

const route = useRoute()

function rolarPara(id: string) {
  if (typeof document === 'undefined') return
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function acao(action: string) {
  switch (action) {
    case 'ver-pedido':
      navigateTo(`/pedidos/${props.ingresso.pedidoId}`)
      break
    case 'ver-pagamento':
      navigateTo(`/pedidos/${props.ingresso.pedidoId}#order-payment`)
      break
    case 'ver-evento':
      navigateTo(`/eventos/${props.ingresso.eventoId}/lotes`)
      break
    case 'ver-utilizacao':
      rolarPara('ticket-usage')
      break
    case 'ver-historico':
      rolarPara('ticket-timeline')
      break
  }
}

onMounted(() => {
  const hash = route.hash.replace('#', '')
  if (hash) rolarPara(hash)
})
</script>

<template>
  <div class="mx-auto w-full max-w-6xl space-y-6">
    <TicketDetailHeader :ingresso="props.ingresso">
      <template #actions>
        <TicketDetailActions :status="props.ingresso.status" @action="acao" />
      </template>
    </TicketDetailHeader>

    <div class="grid grid-cols-1 gap-5 lg:grid-cols-3">
      <div class="space-y-5 lg:col-span-2">
        <TicketQrCard :ingresso="props.ingresso" />
        <TicketOverviewCard :ingresso="props.ingresso" />
        <TicketTimeline :eventos="props.ingresso.historico" />
      </div>

      <div class="space-y-5">
        <TicketParticipantCard :ingresso="props.ingresso" />
        <TicketEventCard :ingresso="props.ingresso" />
        <TicketUsageCard :ingresso="props.ingresso" />
      </div>
    </div>
  </div>
</template>
