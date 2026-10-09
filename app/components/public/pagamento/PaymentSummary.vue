<script setup lang="ts">
import { formatMoeda } from '~/utils/format'
import type { CheckoutPublico } from '~/types/checkoutPagamento'

const props = defineProps<{
  checkout: CheckoutPublico
}>()
</script>

<template>
  <dl class="space-y-2 rounded-xl border border-zinc-800 bg-zinc-950/60 p-4 text-sm">
    <div class="flex items-start justify-between gap-3">
      <dt class="text-zinc-500">Evento</dt>
      <dd class="text-right text-zinc-200">{{ props.checkout.eventoNome }}</dd>
    </div>
    <div class="flex items-center justify-between gap-3">
      <dt class="text-zinc-500">Pedido</dt>
      <dd class="font-semibold text-white">{{ props.checkout.codigoPedido }}</dd>
    </div>
    <div class="flex items-center justify-between gap-3">
      <dt class="text-zinc-500">Lote</dt>
      <dd class="text-zinc-200">{{ props.checkout.loteNome ?? '—' }}</dd>
    </div>
    <div class="flex items-center justify-between gap-3">
      <dt class="text-zinc-500">Quantidade</dt>
      <dd class="text-zinc-200">{{ props.checkout.quantidade }}</dd>
    </div>
    <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-2">
      <dt class="font-medium text-zinc-300">Valor</dt>
      <dd class="text-base font-bold text-amber-400">{{ formatMoeda(props.checkout.valorTotal) }}</dd>
    </div>
  </dl>
</template>
