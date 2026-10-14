<script setup lang="ts">
import PublicTicketsPage from '~/components/public/ingressos/PublicTicketsPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { tituloPublico } from '~/utils/marca'

const { organizacao } = useOrganizacaoPublica()

useSeoMeta({
  title: () => tituloPublico('Meus ingressos', organizacao.value?.nome),
  description: 'Acesse e apresente os ingressos do seu pedido.'
})
</script>

<template>
  <PublicTicketsPage />
</template>
