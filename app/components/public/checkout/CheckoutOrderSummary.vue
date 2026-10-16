<script setup lang="ts">
import { formatMoeda } from '~/utils/format'

const props = withDefaults(
  defineProps<{
    quantidade: number
    preco: number | null
    total: number
    /** Taxa de servico total paga pelo comprador. */
    taxa?: number
    /** Quantos ingressos sao meia-entrada e o preco da meia. */
    quantidadeMeia?: number
    precoMeia?: number | null
  }>(),
  { taxa: 0, quantidadeMeia: 0, precoMeia: null }
)
</script>

<template>
  <section class="rounded-2xl border border-zinc-800 bg-zinc-900 p-5">
    <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Resumo</h3>

    <dl class="mt-3 space-y-2 text-sm">
      <div class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Quantidade</dt>
        <dd class="text-zinc-200">{{ props.quantidade }}</dd>
      </div>
      <template v-if="props.quantidadeMeia > 0">
        <div v-if="props.quantidade > props.quantidadeMeia" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">{{ props.quantidade - props.quantidadeMeia }} × inteira</dt>
          <dd class="text-zinc-200">{{ formatMoeda(props.preco ?? 0) }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">{{ props.quantidadeMeia }} × meia-entrada</dt>
          <dd class="text-zinc-200">{{ formatMoeda(props.precoMeia ?? 0) }}</dd>
        </div>
      </template>
      <div v-else class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Preço unitário</dt>
        <dd class="text-zinc-200">{{ formatMoeda(props.preco ?? 0) }}</dd>
      </div>
      <div v-if="props.taxa > 0" class="flex items-center justify-between gap-3">
        <dt class="text-zinc-500">Taxa de serviço</dt>
        <dd class="text-zinc-200">{{ formatMoeda(props.taxa) }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-2">
        <dt class="font-medium text-zinc-300">Total</dt>
        <dd class="text-base font-bold text-amber-400">{{ formatMoeda(props.total) }}</dd>
      </div>
    </dl>
  </section>
</template>
