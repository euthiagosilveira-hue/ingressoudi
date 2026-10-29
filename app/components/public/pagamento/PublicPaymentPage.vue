<script setup lang="ts">
import { computed, watch } from 'vue'

import PaymentApprovedState from '~/components/public/pagamento/PaymentApprovedState.vue'
import PaymentError from '~/components/public/pagamento/PaymentError.vue'
import PaymentExpiredState from '~/components/public/pagamento/PaymentExpiredState.vue'
import PaymentHeader from '~/components/public/pagamento/PaymentHeader.vue'
import PaymentLoading from '~/components/public/pagamento/PaymentLoading.vue'
import PaymentPendingCard from '~/components/public/pagamento/PaymentPendingCard.vue'
import PaymentUnavailableState from '~/components/public/pagamento/PaymentUnavailableState.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { usePublicPayment } from '~/composables/usePublicPayment'
import { removerPedidoSalvo, salvarPedido } from '~/utils/ingressosSalvos'
import { rotaIngressosPedido } from '~/utils/rotasPublicas'

const {
  token,
  checkout,
  carregando,
  mensagemErro,
  estado,
  textoCountdown,
  tempoEsgotado,
  pix,
  pixCarregando,
  pixErro,
  verificandoExpiracao,
  carregar,
  atualizar,
  tentarPix
} = usePublicPayment()

const eventoSlug = computed(() => checkout.value?.eventoSlug ?? '')
const eventoNome = computed(() => checkout.value?.eventoNome ?? 'Checkout')

const { definir: definirOrganizacao } = useOrganizacaoPublica()
watch(
  checkout,
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

// Guarda o pedido neste aparelho para o comprador voltar em "Meus ingressos".
watch(
  [checkout, estado],
  ([valor, situacao]) => {
    if (!valor || !token.value) return
    if (['EXPIRADO', 'CANCELADO', 'REJEITADO', 'REEMBOLSADO'].includes(situacao)) {
      removerPedidoSalvo(valor.pedidoId)
      return
    }
    if (situacao !== 'PENDENTE' && situacao !== 'PAGO') return
    salvarPedido({
      pedidoId: valor.pedidoId,
      checkoutToken: token.value,
      codigoPedido: valor.codigoPedido,
      organizacaoSlug: valor.organizacaoSlug ?? null,
      eventoSlug: valor.eventoSlug,
      eventoNome: valor.eventoNome,
      quantidade: valor.quantidade
    })
  },
  { immediate: true }
)

// Pagamento confirmado (inclusive quando o comprador volta do banco): abre os
// ingressos sozinho, sem precisar de clique.
let abriuIngressos = false
watch(
  estado,
  (situacao) => {
    if (abriuIngressos || situacao !== 'PAGO' || !import.meta.client) return
    const valor = checkout.value
    if (!valor || !token.value || !valor.eventoSlug) return
    abriuIngressos = true
    void navigateTo(rotaIngressosPedido(valor.organizacaoSlug, valor.eventoSlug, token.value), {
      replace: true
    })
  },
  { immediate: true }
)
</script>

<template>
  <div class="mx-auto w-full max-w-3xl px-4 py-6 sm:px-6 sm:py-10">
    <PaymentLoading v-if="carregando" />

    <PaymentError
      v-else-if="estado === 'ERRO'"
      :mensagem="mensagemErro"
      @retry="carregar"
    />

    <PaymentUnavailableState
      v-else-if="estado === 'NAO_ENCONTRADO'"
      titulo="Checkout não encontrado ou indisponível."
      descricao="Verifique o link utilizado ou inicie uma nova compra."
      tom="neutro"
    />

    <template v-else>
      <PaymentHeader :evento-slug="eventoSlug" :evento-nome="eventoNome" />

      <div class="mt-6">
        <PaymentPendingCard
          v-if="estado === 'PENDENTE' && checkout"
          :checkout="checkout"
          :texto-countdown="textoCountdown"
          :tempo-esgotado="tempoEsgotado"
          :pix="pix"
          :pix-carregando="pixCarregando"
          :pix-erro="pixErro"
          :verificando="verificandoExpiracao"
          @atualizar="atualizar"
          @tentar-pix="tentarPix"
        />

        <PaymentApprovedState
          v-else-if="estado === 'PAGO' && checkout"
          :checkout="checkout"
          :slug="eventoSlug"
          :checkout-token="token"
        />

        <PaymentExpiredState
          v-else-if="estado === 'EXPIRADO'"
          :evento-slug="eventoSlug"
        />

        <PaymentUnavailableState
          v-else-if="estado === 'CANCELADO'"
          titulo="Pedido cancelado"
          descricao="Este pedido foi cancelado e não pode ser pago."
          :evento-slug="eventoSlug"
        />

        <PaymentUnavailableState
          v-else-if="estado === 'REJEITADO'"
          titulo="Pagamento não aprovado"
          descricao="O pagamento não foi aprovado. Nenhuma nova cobrança será criada automaticamente."
          :evento-slug="eventoSlug"
          tom="alerta"
        />

        <PaymentUnavailableState
          v-else-if="estado === 'REEMBOLSADO'"
          titulo="Pagamento reembolsado"
          descricao="Este pagamento foi reembolsado."
          :evento-slug="eventoSlug"
        />
      </div>
    </template>
  </div>
</template>
