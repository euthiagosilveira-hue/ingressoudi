<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import type { TicketStatus } from '~/types/ingresso'

const props = defineProps<{
  status: TicketStatus
}>()

const emit = defineEmits<{
  action: [action: string]
}>()
</script>

<template>
  <AppButton variant="outline" @click="emit('action', 'ver-pedido')">Ver pedido</AppButton>
  <AppButton variant="ghost" @click="emit('action', 'ver-evento')">Ver evento</AppButton>

  <AppButton
    v-if="props.status === 'UTILIZADO'"
    variant="ghost"
    @click="emit('action', 'ver-utilizacao')"
  >
    Ver utilização
  </AppButton>

  <AppButton
    v-if="props.status === 'RESERVADO'"
    variant="ghost"
    @click="emit('action', 'ver-pagamento')"
  >
    Ver pagamento
  </AppButton>

  <AppButton
    v-if="props.status === 'CANCELADO'"
    variant="ghost"
    @click="emit('action', 'ver-historico')"
  >
    Ver histórico
  </AppButton>
</template>
