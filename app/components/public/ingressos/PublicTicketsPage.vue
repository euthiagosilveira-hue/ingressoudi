<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ChatBubbleLeftRightIcon } from '@heroicons/vue/24/outline'

import PublicOrderSummary from '~/components/public/ingressos/PublicOrderSummary.vue'
import PublicTicketCard from '~/components/public/ingressos/PublicTicketCard.vue'
import PublicTicketsError from '~/components/public/ingressos/PublicTicketsError.vue'
import PublicTicketsHeader from '~/components/public/ingressos/PublicTicketsHeader.vue'
import PublicTicketsLoading from '~/components/public/ingressos/PublicTicketsLoading.vue'
import PublicTicketsUnavailable from '~/components/public/ingressos/PublicTicketsUnavailable.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { usePublicTickets } from '~/composables/usePublicTickets'
import { removerPedidoSalvo, salvarPedido } from '~/utils/ingressosSalvos'
import { linkWhatsappIngressos, mensagemTicketsErro } from '~/utils/publicIngressos'
import { rotaIngressosPedido } from '~/utils/rotasPublicas'

const { token, recoveryToken, tickets, carregando, erro, estado, carregar } = usePublicTickets()

const { definir: definirOrganizacao } = useOrganizacaoPublica()
watch(
  tickets,
  (valor) => {
    if (valor) {
      definirOrganizacao({
        slug: valor.organizacaoSlug,
        nome: valor.organizacaoNome,
        logoUrl: valor.organizacaoLogoUrl
      })
    }
  },
  { immediate: true }
)

// Abriu pelo link da compra: guarda neste aparelho para achar depois em "Meus ingressos".
watch(
  tickets,
  (valor) => {
    if (!valor || !token.value) return
    if (valor.pedidoStatus === 'CANCELADO' || valor.pedidoStatus === 'EXPIRADO') {
      removerPedidoSalvo(valor.pedidoId)
      return
    }
    salvarPedido({
      pedidoId: valor.pedidoId,
      checkoutToken: token.value,
      codigoPedido: valor.codigoPedido,
      organizacaoSlug: valor.organizacaoSlug ?? null,
      eventoSlug: valor.eventoSlug,
      eventoNome: valor.eventoNome,
      eventoInicioEm: valor.eventoInicioEm,
      eventoLocal: valor.eventoLocal,
      quantidade: valor.ingressos.length || null
    })
  },
  { immediate: true }
)

// Link permanente da compra (checkout_token) para o comprador mandar ao proprio
// WhatsApp. Pelo acesso de recuperacao o link expira, entao o botao nao aparece.
const origem = ref('')
onMounted(() => {
  origem.value = window.location.origin
})
const linkWhatsapp = computed(() => {
  const valor = tickets.value
  if (!valor || !token.value || !origem.value) return null
  const url = origem.value + rotaIngressosPedido(valor.organizacaoSlug, valor.eventoSlug, token.value)
  return linkWhatsappIngressos({ url, eventoNome: valor.eventoNome })
})

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

        <div v-if="linkWhatsapp" class="space-y-2">
          <a
            :href="linkWhatsapp"
            target="_blank"
            rel="noopener"
            class="flex w-full items-center justify-center gap-2 rounded-xl bg-green-500 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-green-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-400/60"
          >
            <ChatBubbleLeftRightIcon class="h-5 w-5" />
            Enviar para meu WhatsApp
          </a>
          <p class="text-center text-xs text-zinc-500">
            Mande o link para você mesmo e não perca seus ingressos.
          </p>
        </div>

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
