<script setup lang="ts">
import { computed } from 'vue'

import PublicOrderSummary from '~/components/public/ingressos/PublicOrderSummary.vue'
import PublicTicketCard from '~/components/public/ingressos/PublicTicketCard.vue'
import PublicTicketsError from '~/components/public/ingressos/PublicTicketsError.vue'
import PublicTicketsHeader from '~/components/public/ingressos/PublicTicketsHeader.vue'
import PublicTicketsLoading from '~/components/public/ingressos/PublicTicketsLoading.vue'
import PublicTicketsUnavailable from '~/components/public/ingressos/PublicTicketsUnavailable.vue'
import { usePublicTickets } from '~/composables/usePublicTickets'
import { mensagemTicketsErro } from '~/utils/publicIngressos'

const { token, recoveryToken, tickets, carregando, erro, estado, carregar } = usePublicTickets()

const tituloIndisponivel = computed(() => {
  const status = tickets.value?.pedidoStatus
  if (status === 'CANCELADO') return 'Pedido cancelado'
  if (status === 'EXPIRADO') return 'Reserva expirada'
  return 'Ingressos ainda não disponíveis'
})

const descricaoIndisponivel = computed(() => {
  const status = tickets.value?.pedidoStatus
  if (status === 'CANCELADO') {
    return 'Este pedido foi cancelado. Os ingressos não estão disponíveis para entrada.'
  }
  if (status === 'EXPIRADO') {
    return 'Esta reserva expirou e os ingressos não estão mais disponíveis.'
  }
  return 'Seus ingressos ainda não estão disponíveis. Finalize o pagamento para acessá-los.'
})
</script>

<template>
  <div class="mx-auto w-full max-w-3xl px-4 py-6 sm:px-6 sm:py-10">
    <PublicTicketsLoading v-if="carregando" />

    <PublicTicketsError
      v-else-if="estado === 'ERRO'"
      :mensagem="mensagemTicketsErro(erro ?? 'ERRO_INESPERADO')"
      @retry="carregar"
    />

    <PublicTicketsError
      v-else-if="estado === 'NAO_ENCONTRADO'"
      mensagem="Não foi possível localizar seus ingressos."
      @retry="carregar"
    />

    <PublicTicketsUnavailable
      v-else-if="estado === 'INDISPONIVEL' && tickets"
      :titulo="tituloIndisponivel"
      :descricao="descricaoIndisponivel"
      :evento-slug="tickets.eventoSlug"
      :checkout-token="token"
    />

    <template v-else-if="tickets">
      <PublicTicketsHeader :evento-slug="tickets.eventoSlug" :evento-nome="tickets.eventoNome" />

      <div class="mt-6 space-y-6">
        <PublicOrderSummary :tickets="tickets" />

        <div class="space-y-4">
          <PublicTicketCard
            v-for="ingresso in tickets.ingressos"
            :key="ingresso.ingressoId"
            :ticket="ingresso"
            :evento-nome="tickets.eventoNome"
            :evento-inicio-em="tickets.eventoInicioEm"
            :evento-local="tickets.eventoLocal"
            :checkout-token="token"
            :recovery-token="recoveryToken"
          />
        </div>

        <button
          type="button"
          class="flex w-full items-center justify-center rounded-xl border border-zinc-700 px-6 py-3 text-xs font-bold uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
          @click="carregar"
        >
          Atualizar ingressos
        </button>
      </div>
    </template>
  </div>
</template>
