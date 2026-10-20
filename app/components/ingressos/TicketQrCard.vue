<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatDataHoraCompleta } from '~/utils/format'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()

const bloqueio = computed<{ descricao: string } | null>(() => {
  if (props.ingresso.status === 'RESERVADO') {
    return { descricao: 'Disponível após confirmação do pagamento.' }
  }
  if (props.ingresso.status === 'EXPIRADO') {
    return { descricao: 'Este ingresso expirou junto com a reserva.' }
  }
  if (props.ingresso.status === 'CANCELADO') {
    return { descricao: 'Este ingresso foi cancelado e não pode ser utilizado.' }
  }
  return null
})

const utilizado = computed(() => props.ingresso.status === 'UTILIZADO')
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Código do ingresso</h2>

    <div
      class="rounded-xl border border-white/10 bg-zinc-950/60 px-4 py-6 text-center"
      :class="bloqueio ? 'opacity-60' : ''"
    >
      <p class="font-mono text-2xl font-semibold tracking-wider text-white">{{ props.ingresso.codigo }}</p>
      <p v-if="bloqueio" class="mt-2 text-sm text-zinc-400">{{ bloqueio.descricao }}</p>
      <p v-else-if="utilizado" class="mt-2 text-sm text-green-300">
        Entrada registrada em {{ formatDataHoraCompleta(props.ingresso.utilizadoEm ?? '') }}.
      </p>
      <p v-else class="mt-2 text-sm text-green-300">Válido para entrada.</p>
    </div>

    <p class="text-center text-xs text-zinc-500">
      Por segurança, o QR Code fica só com o comprador, em "Meus ingressos". Na portaria, o participante também
      pode ser encontrado pela busca por nome.
    </p>
  </BaseCard>
</template>
