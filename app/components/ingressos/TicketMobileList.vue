<script setup lang="ts">
import TicketMobileCard from '~/components/ingressos/TicketMobileCard.vue'
import type { TicketListItem } from '~/types/ingresso'

const props = defineProps<{
  ingressos: TicketListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; pedidoId: string; eventoId: string; action: string }]
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <TicketMobileCard
      v-for="ingresso in props.ingressos"
      :key="ingresso.id"
      :ingresso="ingresso"
      @action="emit('action', $event)"
    />
  </div>
</template>
