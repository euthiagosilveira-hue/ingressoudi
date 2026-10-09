<script setup lang="ts">
import PaymentMobileCard from '~/components/financeiro/PaymentMobileCard.vue'
import type { PaymentListItem } from '~/types/pagamento'

const props = defineProps<{
  pagamentos: PaymentListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; action: string }]
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <PaymentMobileCard
      v-for="pagamento in props.pagamentos"
      :key="pagamento.id"
      :pagamento="pagamento"
      @action="emit('action', $event)"
    />
  </div>
</template>
