<script setup lang="ts">
import { computed } from 'vue'

import type { PublicVendaSituacao } from '~/types/publicEvento'

const props = defineProps<{
  situacao: Exclude<PublicVendaSituacao, 'DISPONIVEL'>
}>()

interface Config {
  titulo: string
  descricao: string
  classes: string
}

const mapa: Record<Exclude<PublicVendaSituacao, 'DISPONIVEL'>, Config> = {
  ESGOTADO: {
    titulo: 'Esgotado',
    descricao: 'Os ingressos disponíveis para venda antecipada se esgotaram.',
    classes: 'border-zinc-700 bg-zinc-800/60 text-zinc-300'
  },
  SEM_LOTE: {
    titulo: 'Em breve',
    descricao: 'Os ingressos ainda não estão disponíveis para venda.',
    classes: 'border-zinc-700 bg-zinc-800/60 text-zinc-300'
  },
  VENDAS_ENCERRADAS: {
    titulo: 'Vendas encerradas',
    descricao: 'As vendas para este evento foram encerradas.',
    classes: 'border-zinc-700 bg-zinc-800/60 text-zinc-300'
  },
  EVENTO_EM_ANDAMENTO: {
    titulo: 'Evento em andamento',
    descricao: 'Este evento já começou.',
    classes: 'border-green-500/30 bg-green-500/10 text-green-200'
  },
  ENCERRADO: {
    titulo: 'Evento encerrado',
    descricao: 'Este evento já foi encerrado.',
    classes: 'border-zinc-700 bg-zinc-800/60 text-zinc-400'
  },
  CANCELADO: {
    titulo: 'Evento cancelado',
    descricao: 'As vendas estão indisponíveis.',
    classes: 'border-red-500/40 bg-red-500/10 text-red-200'
  }
}

const config = computed(() => mapa[props.situacao])
</script>

<template>
  <div class="rounded-xl border p-4" :class="config.classes" role="status">
    <p class="text-sm font-bold uppercase tracking-wide">{{ config.titulo }}</p>
    <p class="mt-1 text-sm opacity-90">{{ config.descricao }}</p>
  </div>
</template>
