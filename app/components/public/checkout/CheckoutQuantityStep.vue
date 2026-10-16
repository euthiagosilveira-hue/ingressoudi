<script setup lang="ts">
import { computed } from 'vue'

import QuantitySelector from '~/components/public/checkout/QuantitySelector.vue'
import { formatMoeda } from '~/utils/format'

const props = defineProps<{
  loteNome: string | null
  preco: number | null
  quantidade: number
  disponiveis: number | null
  maximo: number
  /** Preco da meia quando o evento tem meia-entrada (senao null). */
  precoMeia?: number | null
  /** Soma dos ingressos ja considerando as meias escolhidas. */
  subtotal?: number
}>()

const emit = defineEmits<{
  'update:quantidade': [value: number]
}>()

const subtotal = computed(() => props.subtotal ?? (props.preco ?? 0) * props.quantidade)
const ultimos = computed(() => props.disponiveis !== null && props.disponiveis <= 10)
const disponibilidadeTexto = computed(() =>
  props.disponiveis !== null ? `${props.disponiveis} ingressos disponíveis` : ''
)
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <h2 class="text-lg font-semibold text-white">Quantidade</h2>

    <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
      <p class="text-xs uppercase tracking-wide text-zinc-500">Lote atual</p>
      <p class="text-sm font-semibold text-white">{{ props.loteNome ?? 'Lote' }}</p>
      <template v-if="props.precoMeia != null">
        <div class="mt-2 flex flex-wrap items-end gap-x-6 gap-y-2">
          <div>
            <p class="text-xs text-zinc-500">Inteira</p>
            <p class="text-2xl font-bold text-amber-400">{{ formatMoeda(props.preco ?? 0) }}</p>
          </div>
          <div>
            <p class="text-xs text-zinc-500">Meia-entrada</p>
            <p class="text-2xl font-bold text-amber-400">{{ formatMoeda(props.precoMeia) }}</p>
          </div>
        </div>
        <p class="mt-1 text-xs text-zinc-500">por ingresso · você escolhe inteira ou meia no próximo passo</p>
      </template>
      <template v-else>
        <p class="mt-2 text-2xl font-bold text-amber-400">{{ formatMoeda(props.preco ?? 0) }}</p>
        <p class="text-xs text-zinc-500">por ingresso</p>
      </template>
    </div>

    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <QuantitySelector
        :model-value="props.quantidade"
        :max="props.maximo"
        @update:model-value="emit('update:quantidade', $event)"
      />
      <div class="sm:text-right">
        <p class="text-xs text-zinc-500">Subtotal</p>
        <p class="text-xl font-bold text-white">{{ formatMoeda(subtotal) }}</p>
      </div>
    </div>

    <p
      v-if="disponibilidadeTexto"
      class="text-sm"
      :class="ultimos ? 'text-amber-300' : 'text-zinc-400'"
    >
      {{ disponibilidadeTexto }}<span v-if="ultimos"> · Últimos ingressos</span>
    </p>
  </section>
</template>
