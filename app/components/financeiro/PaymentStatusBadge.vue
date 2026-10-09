<script setup lang="ts">
import OrderPaymentStatusBadge from '~/components/pedidos/OrderPaymentStatusBadge.vue'
import type { FinancialPaymentStatus } from '~/types/pagamento'

defineProps<{
  status: FinancialPaymentStatus
}>()
</script>

<template>
  <OrderPaymentStatusBadge :status="status" />
</template>
