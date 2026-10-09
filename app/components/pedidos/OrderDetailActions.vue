<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import type { OrderStatus } from '~/types/pedido'

const props = defineProps<{
  status: OrderStatus
  temReembolso: boolean
}>()

const emit = defineEmits<{
  action: [action: string]
}>()
</script>

<template>
  <template v-if="props.status === 'RESERVADO'">
    <AppButton variant="outline" @click="emit('action', 'ver-pagamento')">Ver pagamento</AppButton>
  </template>

  <template v-else-if="props.status === 'PAGO'">
    <AppButton variant="outline" @click="emit('action', 'ver-ingressos')">Ver ingressos</AppButton>
    <AppButton variant="ghost" @click="emit('action', 'solicitar-reembolso')">
      Solicitar reembolso
    </AppButton>
  </template>

  <template v-else-if="props.status === 'CANCELADO'">
    <AppButton variant="outline" @click="emit('action', 'ver-historico')">Ver histórico</AppButton>
    <AppButton
      v-if="props.temReembolso"
      variant="outline"
      @click="emit('action', 'ver-reembolso')"
    >
      Ver reembolso
    </AppButton>
  </template>
</template>
