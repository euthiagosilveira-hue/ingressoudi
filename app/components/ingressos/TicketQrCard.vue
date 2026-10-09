<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatDataHoraCompleta } from '~/utils/format'
import { gerarPadraoQrMock } from '~/utils/ingressos'
import type { TicketDetail } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketDetail
}>()

const modulos = computed(() => {
  const itens: Array<{ x: number; y: number }> = []
  gerarPadraoQrMock(props.ingresso.qrMockValue, 21).forEach((linha, y) => {
    linha.forEach((ativo, x) => {
      if (ativo) itens.push({ x, y })
    })
  })
  return itens
})

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
    <div class="flex items-center justify-between gap-3">
      <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">QR Code</h2>
      <span
        class="inline-flex items-center rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
      >
        Mock
      </span>
    </div>

    <div class="relative mx-auto w-full max-w-[280px]">
      <div class="rounded-xl bg-white p-3" :class="bloqueio ? 'opacity-30' : ''">
        <svg
          viewBox="0 0 21 21"
          class="h-auto w-full"
          role="img"
          :aria-label="`QR de demonstração do ingresso ${props.ingresso.codigo}`"
        >
          <rect width="21" height="21" fill="#ffffff" />
          <rect
            v-for="modulo in modulos"
            :key="`${modulo.x}-${modulo.y}`"
            :x="modulo.x"
            :y="modulo.y"
            width="1"
            height="1"
            fill="#18181b"
          />
        </svg>
      </div>

      <div
        v-if="bloqueio"
        class="absolute inset-0 flex flex-col items-center justify-center rounded-xl bg-zinc-950/70 px-4 text-center"
      >
        <p class="text-sm font-semibold text-zinc-100">QR indisponível</p>
        <p class="mt-1 text-xs text-zinc-400">{{ bloqueio.descricao }}</p>
      </div>
    </div>

    <p class="text-center text-sm font-semibold text-white">{{ props.ingresso.codigo }}</p>
    <p class="text-center text-sm text-zinc-400">
      Apresente este ingresso na entrada do evento.
    </p>
    <p v-if="utilizado" class="text-center text-xs text-green-300">
      Entrada registrada em {{ formatDataHoraCompleta(props.ingresso.utilizadoEm ?? '') }}.
    </p>
    <p class="text-center text-[11px] text-zinc-500">
      QR de demonstração — integração real será feita posteriormente.
    </p>
  </BaseCard>
</template>
