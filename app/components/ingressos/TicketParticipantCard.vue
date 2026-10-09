<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Participante
    </h2>

    <div>
      <p class="break-words text-sm font-medium text-zinc-100">
        {{ props.ingresso.participanteNome }}
      </p>
      <p class="mt-1 text-xs text-zinc-500">Nome vinculado ao ingresso.</p>
    </div>

    <p
      v-if="props.ingresso.pedidoStatus === 'PAGO'"
      class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3 text-xs text-zinc-400"
    >
      Não pode ser alterado após a confirmação do pagamento.
    </p>
  </BaseCard>
</template>
