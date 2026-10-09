<script setup lang="ts">
import { formatData, formatHora, formatMoeda } from '~/utils/format'
import type { CheckoutBuyer, CheckoutParticipant, CheckoutStep } from '~/types/checkout'
import type { PublicEventDetail } from '~/types/publicEvento'

const props = withDefaults(
  defineProps<{
    evento: PublicEventDetail
    quantidade: number
    preco: number | null
    total: number
    participantes: CheckoutParticipant[]
    comprador: CheckoutBuyer
    erro?: string
  }>(),
  { erro: '' }
)

const emit = defineEmits<{
  editar: [step: CheckoutStep]
}>()

const acaoEditar =
  'text-xs font-semibold uppercase tracking-wide text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50'
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <h2 class="text-lg font-semibold text-white">Revisão</h2>

    <div class="space-y-4">
      <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="text-xs uppercase tracking-wide text-zinc-500">Evento</p>
            <p class="text-sm font-semibold text-white">{{ props.evento.nome }}</p>
            <p class="mt-1 text-xs text-zinc-400">
              {{ formatData(props.evento.inicioEm) }} • {{ formatHora(props.evento.inicioEm) }}
            </p>
            <p class="text-xs text-zinc-500">{{ props.evento.local }}</p>
            <p class="mt-1 text-xs text-zinc-400">Lote: {{ props.evento.loteNome ?? 'Lote' }}</p>
          </div>
          <button type="button" :class="acaoEditar" @click="emit('editar', 'QUANTIDADE')">
            Editar quantidade
          </button>
        </div>
      </div>

      <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
        <div class="flex items-center justify-between gap-3">
          <p class="text-xs uppercase tracking-wide text-zinc-500">
            Participantes ({{ props.participantes.length }})
          </p>
          <button type="button" :class="acaoEditar" @click="emit('editar', 'PARTICIPANTES')">
            Editar participantes
          </button>
        </div>
        <ol class="mt-2 space-y-1 text-sm text-zinc-200">
          <li v-for="(participante, indice) in props.participantes" :key="indice">
            {{ indice + 1 }}. {{ participante.nome }}
          </li>
        </ol>
      </div>

      <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
        <div class="flex items-center justify-between gap-3">
          <p class="text-xs uppercase tracking-wide text-zinc-500">Comprador</p>
          <button type="button" :class="acaoEditar" @click="emit('editar', 'COMPRADOR')">
            Editar comprador
          </button>
        </div>
        <div class="mt-2 space-y-1 text-sm text-zinc-200">
          <p>{{ props.comprador.nome }}</p>
          <p>{{ props.comprador.telefone }}</p>
          <p>{{ props.comprador.email }}</p>
        </div>
      </div>

      <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
        <p class="text-xs uppercase tracking-wide text-zinc-500">Valores</p>
        <div class="mt-2 space-y-1 text-sm">
          <p class="text-zinc-300">
            {{ props.quantidade }} × {{ formatMoeda(props.preco ?? 0) }}
          </p>
          <p class="text-base font-bold text-amber-400">
            Total: {{ formatMoeda(props.total) }}
          </p>
        </div>
      </div>
    </div>

    <p class="border-t border-zinc-800 pt-4 text-xs text-zinc-500">
      Após a confirmação do pagamento, os nomes dos participantes não poderão ser alterados.
    </p>

    <p
      v-if="props.erro"
      role="alert"
      class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-200"
    >
      {{ props.erro }}
    </p>
  </section>
</template>
