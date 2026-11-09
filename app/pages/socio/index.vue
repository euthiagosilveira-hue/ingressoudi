<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ArrowPathIcon, CalendarDaysIcon, ChevronRightIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import PageHeader from '~/components/PageHeader.vue'
import { listarEventosSocio } from '~/services/socio'
import { formatDataHora, formatMoeda } from '~/utils/format'
import { percentualVendido, type EventoSocio } from '~/utils/socio'

definePageMeta({
  title: 'Vendas',
  description: 'Acompanhe as vendas dos eventos em que você é sócio.',
  layout: 'admin-layout',
  sidebarActive: 'Vendas',
  middleware: ['socio-auth']
})

const eventos = ref<EventoSocio[]>([])
const carregando = ref(true)
const erro = ref('')

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    eventos.value = await listarEventosSocio()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar as vendas.'
  } finally {
    carregando.value = false
  }
}

onMounted(carregar)
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Vendas dos meus eventos" subtitle="Números atualizados de cada evento em que você é sócio.">
      <template #actions>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-xl border border-zinc-700 px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-zinc-300 transition-colors hover:border-zinc-600 hover:text-white disabled:opacity-50"
          :disabled="carregando"
          @click="carregar"
        >
          <ArrowPathIcon class="h-4 w-4" :class="carregando ? 'animate-spin' : ''" />
          Atualizar
        </button>
      </template>
    </PageHeader>

    <div v-if="carregando && !eventos.length" class="space-y-3" aria-busy="true">
      <div v-for="n in 2" :key="n" class="h-36 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>

    <div
      v-else-if="erro"
      role="alert"
      class="rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center text-sm font-semibold text-red-300"
    >
      {{ erro }}
    </div>

    <div
      v-else-if="!eventos.length"
      class="rounded-2xl border border-zinc-800 bg-zinc-900 p-8 text-center"
    >
      <p class="text-base font-semibold text-white">Nenhum evento liberado ainda</p>
      <p class="mt-1 text-sm text-zinc-400">
        Peça ao produtor para marcar os eventos que você acompanha no seu cadastro.
      </p>
    </div>

    <div v-else class="grid grid-cols-1 gap-4 xl:grid-cols-2">
      <NuxtLink
        v-for="evento in eventos"
        :key="evento.eventoId"
        :to="`/socio/${evento.eventoId}`"
        class="group flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-4 transition-colors hover:border-amber-400/40 sm:flex-row sm:p-5"
      >
        <img
          v-if="evento.imagemUrl"
          :src="evento.imagemUrl"
          alt=""
          class="h-36 w-full shrink-0 rounded-xl object-cover sm:h-28 sm:w-28"
        />
        <div class="min-w-0 flex-1 space-y-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="truncate text-base font-bold text-white">{{ evento.nome }}</p>
              <p class="mt-0.5 flex items-center gap-1.5 text-xs text-zinc-400">
                <CalendarDaysIcon class="h-3.5 w-3.5" /> {{ formatDataHora(evento.inicioEm) }}
              </p>
              <p v-if="evento.local" class="flex items-center gap-1.5 text-xs text-zinc-500">
                <MapPinIcon class="h-3.5 w-3.5" /> {{ evento.local }}
              </p>
            </div>
            <ChevronRightIcon class="h-5 w-5 shrink-0 text-zinc-600 transition-colors group-hover:text-amber-400" />
          </div>

          <div>
            <div class="flex items-baseline justify-between text-xs text-zinc-400">
              <span>
                <span class="text-lg font-bold text-white">{{ evento.resumo.vendidos }}</span>
                <template v-if="evento.resumo.capacidade"> de {{ evento.resumo.capacidade }}</template>
                ingressos
              </span>
              <span>{{ percentualVendido(evento.resumo) }}%</span>
            </div>
            <div class="mt-1.5 h-2 overflow-hidden rounded-full bg-zinc-800">
              <div class="h-full rounded-full bg-amber-400" :style="{ width: `${percentualVendido(evento.resumo)}%` }" />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Vendido (bruto)</p>
              <p class="font-semibold text-white">{{ formatMoeda(evento.resumo.bruto) }}</p>
            </div>
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Líquido</p>
              <p class="font-semibold text-green-400">{{ formatMoeda(evento.resumo.liquido) }}</p>
            </div>
          </div>
        </div>
      </NuxtLink>
    </div>
  </div>
</template>
