<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import { formatMoeda } from '~/utils/format'
import { contarMeias } from '~/utils/meiaEntrada'
import type { OrderDetail } from '~/types/pedido'

const props = defineProps<{
  pedido: OrderDetail
}>()

const valorReembolsado = computed(() => props.pedido.pagamento?.valorReembolsado ?? 0)
const totalLiquido = computed(() => props.pedido.valorTotal - valorReembolsado.value)
const quantidadeMeia = computed(() => contarMeias(props.pedido.ingressos ?? []))
</script>

<template>
  <BaseCard class="space-y-4">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Financeiro</h2>

    <dl class="space-y-3">
      <div class="flex items-center justify-between gap-3">
        <dt class="text-sm text-zinc-500">{{ quantidadeMeia > 0 ? 'Valor da inteira' : 'Valor unitário' }}</dt>
        <dd class="text-sm text-zinc-200">{{ formatMoeda(props.pedido.valorUnitario) }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-sm text-zinc-500">Quantidade</dt>
        <dd class="text-sm text-zinc-200">
          {{ props.pedido.quantidade
          }}<template v-if="quantidadeMeia > 0"> ({{ quantidadeMeia }} meia-entrada)</template>
        </dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-sm text-zinc-500">Total</dt>
        <dd class="text-sm font-semibold text-zinc-100">{{ formatMoeda(props.pedido.valorTotal) }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3">
        <dt class="text-sm text-zinc-500">Valor reembolsado</dt>
        <dd class="text-sm text-zinc-200">{{ formatMoeda(valorReembolsado) }}</dd>
      </div>
      <div class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-3">
        <dt class="text-sm font-medium text-zinc-300">Total líquido</dt>
        <dd class="text-sm font-bold text-amber-400">{{ formatMoeda(totalLiquido) }}</dd>
      </div>
    </dl>
  </BaseCard>
</template>
