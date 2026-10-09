<script setup lang="ts">
import { computed, ref } from 'vue'
import { CalendarDaysIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import type { EventListItem, SalesStatus } from '~/types/evento'

const props = defineProps<{
  evento: EventListItem
  estoqueAntecipado: number
  vendidos: number
  disponiveis: number
  totalLotes: number
  lotesAtivos: number
  precoAtual: number | null
  vendasStatus: SalesStatus
}>()

const emit = defineEmits<{
  abrirVendas: []
}>()

const imagemOk = ref(true)
const vendasEncerradas = computed(() => props.vendasStatus === 'ENCERRADAS')
const podeAbrirVendas = computed(
  () => vendasEncerradas.value && props.evento.status !== 'REALIZADO' && props.evento.status !== 'CANCELADO'
)

const metricas = computed(() => [
  { label: 'Estoque antecipado', valor: formatNumero(props.estoqueAntecipado) },
  { label: 'Vendidos', valor: formatNumero(props.vendidos) },
  { label: 'Disponíveis', valor: formatNumero(props.disponiveis) },
  { label: 'Lotes', valor: String(props.totalLotes) }
])

const resumo = computed(() => {
  const ativos = `${props.lotesAtivos} ativo${props.lotesAtivos === 1 ? '' : 's'}`
  const preco = props.precoAtual !== null ? `${formatMoeda(props.precoAtual)} preço atual` : 'sem lote ativo'
  return `${props.totalLotes} lotes · ${ativos} · ${preco}`
})
</script>

<template>
  <BaseCard>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center">
      <div
        v-if="props.evento.imagemUrl && imagemOk"
        class="h-20 w-full shrink-0 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 sm:w-32"
      >
        <img
          :src="props.evento.imagemUrl"
          :alt="props.evento.nome"
          class="h-full w-full object-cover"
          @error="imagemOk = false"
        />
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center gap-2">
          <h2 class="truncate text-lg font-semibold text-white">{{ props.evento.nome }}</h2>
          <EventStatusBadge :status="props.evento.status" />
          <AppButton
            v-if="podeAbrirVendas"
            variant="outline"
            size="sm"
            @click="emit('abrirVendas')"
          >
            Abrir vendas
          </AppButton>
        </div>
        <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-sm text-zinc-400">
          <span class="inline-flex items-center gap-2">
            <CalendarDaysIcon class="h-4 w-4 shrink-0 text-zinc-500" />
            {{ formatDataHora(props.evento.inicioEm) }}
          </span>
          <span class="inline-flex items-center gap-2">
            <MapPinIcon class="h-4 w-4 shrink-0 text-zinc-500" />
            {{ props.evento.local }}
          </span>
        </div>
        <p class="mt-2 text-xs text-zinc-500">{{ resumo }}</p>
      </div>
    </div>

    <div class="mt-4 grid grid-cols-2 gap-3 border-t border-zinc-800 pt-4 sm:grid-cols-4">
      <div v-for="metrica in metricas" :key="metrica.label">
        <p class="text-[11px] uppercase tracking-wide text-zinc-500">{{ metrica.label }}</p>
        <p class="mt-0.5 text-sm font-semibold text-white">{{ metrica.valor }}</p>
      </div>
    </div>
  </BaseCard>
</template>
