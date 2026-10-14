<script setup lang="ts">
import { tituloPublico } from '~/utils/marca'
import PublicPaymentPage from '~/components/public/pagamento/PublicPaymentPage.vue'

useSeoMeta({
  title: tituloPublico('Pagamento'),
  description: 'Acompanhe o pagamento da sua reserva.'
})
</script>

<template>
  <PublicPaymentPage />
</template>
