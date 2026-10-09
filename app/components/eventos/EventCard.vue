<script setup lang="ts">
import { computed, ref } from 'vue'
import { CalendarDaysIcon, MapPinIcon, TicketIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import EventCardActions from '~/components/eventos/EventCardActions.vue'
import EventPublicationBadge from '~/components/eventos/EventPublicationBadge.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import type { EventListItem } from '~/types/evento'

const props = defineProps<{
  event: EventListItem
}>()

const emit = defineEmits<{
  edit: []
  action: [action: string]
}>()

const imagemOk = ref(true)

const iniciais = computed(() =>
  props.event.nome
    .split(' ')
    .filter(Boolean)
    .map((palavra) => palavra.charAt(0))
    .slice(0, 2)
    .join('')
    .toUpperCase()
)

const vendasAbertas = computed(() => props.event.vendasStatus === 'ABERTAS')
</script>

<template>
  <BaseCard
    :padded="false"
    class="group flex h-full flex-col overflow-hidden transition-colors duration-200 hover:border-amber-400/40"
  >
    <!-- Imagem / fallback -->
    <div class="relative aspect-video w-full overflow-hidden bg-zinc-950">
      <img
        v-if="props.event.imagemUrl && imagemOk"
        :src="props.event.imagemUrl"
        :alt="props.event.nome"
        class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
        @error="imagemOk = false"
      />
      <div
        v-else
        class="flex h-full w-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-zinc-800 via-zinc-900 to-black"
      >
        <CalendarDaysIcon class="h-8 w-8 text-amber-400/80" />
        <span class="text-lg font-bold tracking-[0.2em] text-zinc-200">{{ iniciais }}</span>
      </div>

      <div
        class="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-black/40"
      ></div>

      <div class="absolute left-3 top-3">
        <EventStatusBadge :status="props.event.status" />
      </div>
      <div class="absolute right-3 top-3">
        <EventPublicationBadge :status="props.event.publicacaoStatus" />
      </div>
    </div>

    <!-- Conteúdo -->
    <div class="flex flex-1 flex-col p-5">
      <button
        type="button"
        class="cursor-pointer truncate text-left text-lg font-semibold text-white transition-colors hover:text-amber-400 focus-visible:outline-none focus-visible:text-amber-400"
        @click="emit('edit')"
      >
        {{ props.event.nome }}
      </button>

      <div class="mt-2 flex items-center gap-2 text-sm text-zinc-400">
        <CalendarDaysIcon class="h-4 w-4 shrink-0 text-zinc-500" />
        <span class="truncate">{{ formatDataHora(props.event.inicioEm) }}</span>
      </div>
      <div class="mt-1.5 flex items-center gap-2 text-sm text-zinc-400">
        <MapPinIcon class="h-4 w-4 shrink-0 text-zinc-500" />
        <span class="truncate">{{ props.event.local }}</span>
      </div>

      <p
        class="mt-3 text-xs font-medium uppercase tracking-wide"
        :class="vendasAbertas ? 'text-green-400' : 'text-zinc-500'"
      >
        {{ vendasAbertas ? 'Vendas abertas' : 'Vendas encerradas' }}
      </p>

      <!-- Lote atual -->
      <div class="mt-4 rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
        <template v-if="props.event.loteAtual">
          <p class="text-[11px] uppercase tracking-wide text-zinc-500">Lote atual</p>
          <div class="mt-1 flex items-center justify-between gap-3">
            <span class="truncate text-sm text-zinc-200">
              {{ props.event.loteAtual.nome }}
            </span>
            <span class="shrink-0 text-sm font-semibold text-amber-400">
              {{ formatMoeda(props.event.loteAtual.preco) }}
            </span>
          </div>
        </template>
        <p v-else class="text-sm text-zinc-500">Sem lote ativo</p>
      </div>

      <!-- Resumo -->
      <div class="mt-4 flex items-center gap-6">
        <div class="flex items-center gap-2">
          <TicketIcon class="h-4 w-4 text-zinc-600" />
          <span class="text-sm font-semibold text-white">{{ formatNumero(props.event.vendidos) }}</span>
          <span class="text-xs text-zinc-500">vendidos</span>
        </div>
        <div>
          <span class="text-sm font-semibold text-white">{{ formatNumero(props.event.disponiveis) }}</span>
          <span class="text-xs text-zinc-500"> disponíveis</span>
        </div>
      </div>

      <!-- Rodapé -->
      <div class="mt-5 flex items-center justify-between border-t border-zinc-800 pt-4">
        <AppButton variant="outline" size="sm" @click="emit('edit')">Editar</AppButton>
        <EventCardActions @action="emit('action', $event)" />
      </div>
    </div>
  </BaseCard>
</template>
