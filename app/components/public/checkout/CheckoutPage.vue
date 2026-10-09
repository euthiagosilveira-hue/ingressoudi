<script setup lang="ts">
import { computed } from 'vue'

import CheckoutBuyerStep from '~/components/public/checkout/CheckoutBuyerStep.vue'
import CheckoutEventSummary from '~/components/public/checkout/CheckoutEventSummary.vue'
import CheckoutHeader from '~/components/public/checkout/CheckoutHeader.vue'
import CheckoutNavigation from '~/components/public/checkout/CheckoutNavigation.vue'
import CheckoutOrderSummary from '~/components/public/checkout/CheckoutOrderSummary.vue'
import CheckoutParticipantsStep from '~/components/public/checkout/CheckoutParticipantsStep.vue'
import CheckoutProgress from '~/components/public/checkout/CheckoutProgress.vue'
import CheckoutQuantityStep from '~/components/public/checkout/CheckoutQuantityStep.vue'
import CheckoutReservationCreated from '~/components/public/checkout/CheckoutReservationCreated.vue'
import CheckoutReviewStep from '~/components/public/checkout/CheckoutReviewStep.vue'
import { usePublicCheckout } from '~/composables/usePublicCheckout'
import type { EventoOrigem } from '~/types/checkout'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = withDefaults(
  defineProps<{
    evento: PublicEventDetail
    origem?: EventoOrigem
  }>(),
  { origem: 'SUPABASE' }
)

const {
  step,
  quantidade,
  participantes,
  comprador,
  reserva,
  criando,
  erroReserva,
  errosParticipantes,
  erroCompradorNome,
  erroCompradorTelefone,
  erroCompradorEmail,
  preco,
  disponiveis,
  maximo,
  total,
  definirQuantidade,
  atualizarParticipante,
  proximo,
  voltar,
  irPara
} = usePublicCheckout(props.evento, { origem: props.origem })

const errosComprador = computed(() => ({
  nome: erroCompradorNome.value,
  telefone: erroCompradorTelefone.value,
  email: erroCompradorEmail.value
}))

function aoAtualizarParticipante(payload: { indice: number; valor: string }) {
  atualizarParticipante(payload.indice, payload.valor)
}

function aoVoltar() {
  if (step.value === 'QUANTIDADE') {
    navigateTo(`/eventos/${props.evento.slug}`)
    return
  }
  voltar()
}
</script>

<template>
  <div class="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
    <CheckoutHeader :evento="props.evento" />

    <div v-if="step !== 'RESERVA_CRIADA'" class="mt-6">
      <CheckoutProgress :step="step" />
    </div>

    <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
      <div class="space-y-6 lg:col-span-2">
        <div class="lg:hidden">
          <CheckoutEventSummary :evento="props.evento" />
        </div>

        <CheckoutQuantityStep
          v-if="step === 'QUANTIDADE'"
          :lote-nome="props.evento.loteNome"
          :preco="preco"
          :quantidade="quantidade"
          :disponiveis="disponiveis"
          :maximo="maximo"
          @update:quantidade="definirQuantidade"
        />

        <CheckoutParticipantsStep
          v-else-if="step === 'PARTICIPANTES'"
          :participantes="participantes"
          :erros="errosParticipantes"
          @update:nome="aoAtualizarParticipante"
        />

        <CheckoutBuyerStep
          v-else-if="step === 'COMPRADOR'"
          :comprador="comprador"
          :erros="errosComprador"
          @update:nome="comprador.nome = $event"
          @update:telefone="comprador.telefone = $event"
          @update:email="comprador.email = $event"
        />

        <CheckoutReviewStep
          v-else-if="step === 'REVISAO'"
          :evento="props.evento"
          :quantidade="quantidade"
          :preco="preco"
          :total="total"
          :participantes="participantes"
          :comprador="comprador"
          :erro="erroReserva"
          @editar="irPara"
        />

        <CheckoutReservationCreated
          v-else-if="step === 'RESERVA_CRIADA' && reserva"
          :reserva="reserva"
          :evento="props.evento"
        />

        <div v-if="step !== 'RESERVA_CRIADA'" class="lg:hidden">
          <CheckoutOrderSummary :quantidade="quantidade" :preco="preco" :total="total" />
        </div>

        <CheckoutNavigation
          v-if="step !== 'RESERVA_CRIADA'"
          :step="step"
          :criando="criando"
          @voltar="aoVoltar"
          @proximo="proximo"
        />
      </div>

      <div class="hidden space-y-6 lg:block">
        <CheckoutEventSummary :evento="props.evento" />
        <div v-if="step !== 'RESERVA_CRIADA'">
          <CheckoutOrderSummary :quantidade="quantidade" :preco="preco" :total="total" />
        </div>
      </div>
    </div>
  </div>
</template>
