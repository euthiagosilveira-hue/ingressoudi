<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'

import ConfirmDialog from '~/components/ConfirmDialog.vue'
import OrderBuyerCard from '~/components/pedidos/OrderBuyerCard.vue'
import OrderDetailActions from '~/components/pedidos/OrderDetailActions.vue'
import OrderDetailHeader from '~/components/pedidos/OrderDetailHeader.vue'
import OrderEventCard from '~/components/pedidos/OrderEventCard.vue'
import OrderFinancialCard from '~/components/pedidos/OrderFinancialCard.vue'
import OrderOverviewCard from '~/components/pedidos/OrderOverviewCard.vue'
import OrderPaymentCard from '~/components/pedidos/OrderPaymentCard.vue'
import OrderTicketsCard from '~/components/pedidos/OrderTicketsCard.vue'
import OrderTimeline from '~/components/pedidos/OrderTimeline.vue'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()

const route = useRoute()

const confirmarReembolso = ref(false)

const temReembolso = computed(() => (props.pedido.pagamento?.valorReembolsado ?? 0) > 0)

function rolarPara(id: string) {
  if (typeof document === 'undefined') return
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function acao(action: string) {
  switch (action) {
    case 'ver-pagamento':
      rolarPara('order-payment')
      break
    case 'ver-ingressos':
      rolarPara('order-tickets')
      break
    case 'ver-historico':
      rolarPara('order-timeline')
      break
    case 'ver-reembolso':
      rolarPara('order-payment')
      break
    case 'solicitar-reembolso':
      confirmarReembolso.value = true
      break
  }
}

function confirmarSolicitacaoReembolso() {
  confirmarReembolso.value = false
  toast.success('Solicitação de reembolso registrada (mock).')
}

function visualizarIngresso() {
  toast.info('Visualização do ingresso será implementada na próxima etapa.')
}

onMounted(() => {
  const hash = route.hash.replace('#', '')
  if (hash) rolarPara(hash)
})
</script>

<template>
  <div class="mx-auto w-full max-w-6xl space-y-6">
    <OrderDetailHeader :pedido="props.pedido">
      <template #actions>
        <OrderDetailActions
          :status="props.pedido.status"
          :tem-reembolso="temReembolso"
          @action="acao"
        />
      </template>
    </OrderDetailHeader>

    <div class="grid grid-cols-1 gap-5 lg:grid-cols-3">
      <div class="space-y-5 lg:col-span-2">
        <OrderOverviewCard :pedido="props.pedido" />
        <OrderTicketsCard :pedido="props.pedido" @visualizar="visualizarIngresso" />
        <OrderTimeline :eventos="props.pedido.historico" />
      </div>

      <div class="space-y-5">
        <OrderBuyerCard :pedido="props.pedido" />
        <OrderEventCard :pedido="props.pedido" />
        <OrderFinancialCard :pedido="props.pedido" />
        <OrderPaymentCard :pedido="props.pedido" />
      </div>
    </div>

    <ConfirmDialog
      :open="confirmarReembolso"
      title="Solicitar reembolso?"
      description="A solicitação será registrada para análise. O fluxo completo será implementado na próxima etapa."
      confirm-label="Solicitar reembolso"
      tone="danger"
      @confirm="confirmarSolicitacaoReembolso"
      @cancel="confirmarReembolso = false"
    />
  </div>
</template>
