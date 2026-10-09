<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import LotActivationBadge from '~/components/lotes/LotActivationBadge.vue'
import LotActions from '~/components/lotes/LotActions.vue'
import LotStatusBadge from '~/components/lotes/LotStatusBadge.vue'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import type { LotListItem } from '~/types/lote'

const props = defineProps<{
  lote: LotListItem
  vendasAbertas: boolean
}>()

const emit = defineEmits<{
  action: [action: string]
}>()

const encerrado = computed(() => props.lote.status === 'ENCERRADO')
const esgotado = computed(() => props.lote.disponiveis === 0)
</script>

<template>
  <BaseCard
    class="flex h-full flex-col transition-colors duration-200 hover:border-zinc-700"
    :class="encerrado ? 'opacity-80' : ''"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="truncate text-base font-semibold text-white">{{ props.lote.nome }}</h3>
          <span
            v-if="esgotado"
            class="inline-flex items-center rounded-full border border-zinc-700 bg-zinc-800/70 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-400"
          >
            Esgotado
          </span>
        </div>
        <p class="mt-0.5 text-xs text-zinc-500">{{ props.lote.ordem }}º lote</p>
      </div>
      <LotStatusBadge :status="props.lote.status" />
    </div>

    <p class="mt-4 text-2xl font-bold text-amber-400">{{ formatMoeda(props.lote.preco) }}</p>
    <p class="mt-1 text-sm text-zinc-400">
      {{ formatNumero(props.lote.quantidade) }} ingressos
    </p>

    <div class="mt-4 flex items-center gap-6 rounded-xl border border-zinc-800 bg-zinc-950/60 px-3 py-2.5">
      <div>
        <span class="text-sm font-semibold text-white">{{ formatNumero(props.lote.vendidos) }}</span>
        <span class="ml-1 text-xs text-zinc-500">vendidos</span>
      </div>
      <div>
        <span class="text-sm font-semibold text-white">{{ formatNumero(props.lote.disponiveis) }}</span>
        <span class="ml-1 text-xs text-zinc-500">disponíveis</span>
      </div>
    </div>

    <div class="mt-4 space-y-2">
      <div class="flex items-center justify-between gap-2">
        <span class="text-[11px] uppercase tracking-wide text-zinc-500">Ativação</span>
        <LotActivationBadge :tipo="props.lote.tipoAtivacao" />
      </div>
      <p v-if="props.lote.ativadoEm" class="text-xs text-zinc-500">
        Ativado em {{ formatDataHora(props.lote.ativadoEm) }}
      </p>
      <p v-if="props.lote.encerradoEm" class="text-xs text-zinc-500">
        Encerrado em {{ formatDataHora(props.lote.encerradoEm) }}
      </p>
      <p
        v-if="!props.lote.ativadoEm && !props.lote.encerradoEm && props.lote.ativacaoEm"
        class="text-xs text-zinc-500"
      >
        Ativa em {{ formatDataHora(props.lote.ativacaoEm) }}
      </p>
    </div>

    <div class="mt-auto border-t border-zinc-800 pt-4">
      <div class="pt-0.5">
        <LotActions
          :status="props.lote.status"
          :vendas-abertas="props.vendasAbertas"
          @action="emit('action', $event)"
        />
      </div>
    </div>
  </BaseCard>
</template>
