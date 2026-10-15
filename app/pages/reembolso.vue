<script setup lang="ts">
import LegalPage from '~/components/public/LegalPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'
import { ANTECEDENCIA_MINIMA_HORAS, PRAZO_DESISTENCIA_DIAS } from '~/utils/reembolso'

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `Política de reembolso | ${PLATAFORMA_NOME}`,
  description: `Quando e como pedir o reembolso de ingressos comprados pelo ${PLATAFORMA_NOME}.`
})
</script>

<template>
  <LegalPage titulo="Política de reembolso">
    <p>
      Esta política vale para ingressos comprados online pelo {{ PLATAFORMA_NOME }}. Ela complementa os
      <NuxtLink to="/termos" class="text-amber-400 hover:text-amber-300">Termos de uso</NuxtLink>, de acordo com o Código
      de Defesa do Consumidor.
    </p>

    <h2>1. Desistência da compra</h2>
    <p>
      Você pode desistir da compra e receber o valor de volta em até
      <strong>{{ PRAZO_DESISTENCIA_DIAS }} dias após o pagamento</strong>, desde que o pedido de reembolso seja feito
      <strong>até {{ ANTECEDENCIA_MINIMA_HORAS }} horas antes do início do evento</strong>.
    </p>

    <h2>2. Evento cancelado ou alterado</h2>
    <p>
      Se o evento for cancelado, ou se houver mudança relevante de data, horário ou local, você tem direito ao reembolso
      integral, mesmo fora do prazo de desistência.
    </p>

    <h2>3. Quanto é devolvido</h2>
    <ul>
      <li>Nos casos acima, a devolução é <strong>integral</strong>: valor dos ingressos e a taxa de serviço.</li>
      <li>Compras pagas com Pix são devolvidas por Pix, para a mesma conta que fez o pagamento.</li>
      <li>Vendas feitas em dinheiro na porta são devolvidas diretamente pelo organizador.</li>
    </ul>

    <h2>4. Quando não há reembolso</h2>
    <ul>
      <li>Ingresso que já foi usado para entrar no evento.</li>
      <li>
        Pedido de desistência feito depois de {{ PRAZO_DESISTENCIA_DIAS }} dias da compra ou a menos de
        {{ ANTECEDENCIA_MINIMA_HORAS }} horas do evento, exceto nos casos do item 2.
      </li>
      <li>Não comparecimento ao evento.</li>
    </ul>
    <p>Fora dessas regras, o organizador pode conceder reembolso por decisão própria.</p>

    <h2>5. Como pedir</h2>
    <ul>
      <li>
        Fale com o <strong>organizador do evento</strong>, que é o responsável pelo reembolso. Informe o código do pedido
        (por exemplo, IU100123) e o telefone usado na compra.
      </li>
      <li>Depois da aprovação, os ingressos do pedido são cancelados e deixam de valer na portaria.</li>
      <li>
        O Pix costuma voltar em poucos minutos. Em alguns casos o Mercado Pago leva até alguns dias úteis para concluir.
      </li>
    </ul>
  </LegalPage>
</template>
