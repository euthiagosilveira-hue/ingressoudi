<script setup lang="ts">
import { computed } from 'vue'
import { EyeIcon, PencilSquareIcon, PlayIcon, StopIcon } from '@heroicons/vue/24/outline'

import type { LotStatus } from '~/types/lote'

const props = defineProps<{
  status: LotStatus
  vendasAbertas: boolean
}>()

const emit = defineEmits<{
  action: [action: string]
}>()

const podeEditar = computed(() => props.status !== 'ENCERRADO')
const podeAtivar = computed(() => props.status === 'INATIVO')
const podeEncerrar = computed(() => props.status === 'ATIVO')
const ativacaoBloqueada = computed(() => props.status === 'INATIVO' && !props.vendasAbertas)

const base =
  'inline-flex cursor-pointer items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold uppercase tracking-wide transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50'
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <button
      v-if="podeEditar"
      type="button"
      :class="[base, 'border-zinc-700 text-zinc-200 hover:border-zinc-600 hover:text-white']"
      @click="emit('action', 'editar')"
    >
      <PencilSquareIcon class="h-4 w-4" />
      Editar
    </button>

    <button
      v-if="podeAtivar"
      type="button"
      :title="ativacaoBloqueada ? 'Abra as vendas do evento antes de ativar um lote.' : undefined"
      :class="[
        base,
        ativacaoBloqueada
          ? 'cursor-not-allowed border-zinc-700 text-zinc-500'
          : 'border-green-500/40 bg-green-500/10 text-green-300 hover:bg-green-500/20'
      ]"
      @click="emit('action', ativacaoBloqueada ? 'ativar-bloqueado' : 'ativar')"
    >
      <PlayIcon class="h-4 w-4" />
      Ativar lote
    </button>

    <button
      v-if="podeEncerrar"
      type="button"
      :class="[base, 'border-zinc-700 text-zinc-400 hover:border-red-500/40 hover:text-red-300']"
      @click="emit('action', 'encerrar')"
    >
      <StopIcon class="h-4 w-4" />
      Encerrar
    </button>

    <button
      type="button"
      :class="[base, 'border-transparent text-zinc-400 hover:text-amber-400']"
      @click="emit('action', 'detalhes')"
    >
      <EyeIcon class="h-4 w-4" />
      Detalhes
    </button>
  </div>
</template>
