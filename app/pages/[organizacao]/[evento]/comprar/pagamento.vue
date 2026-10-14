<script setup lang="ts">
import PublicPaymentPage from '~/components/public/pagamento/PublicPaymentPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { tituloPublico } from '~/utils/marca'

const { organizacao } = useOrganizacaoPublica()

useSeoMeta({
  title: () => tituloPublico('Pagamento', organizacao.value?.nome),
  description: 'Acompanhe o pagamento da sua reserva.'
})
</script>

<template>
  <PublicPaymentPage />
</template>
