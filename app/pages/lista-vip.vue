<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ChevronRightIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import PageHeader from '~/components/PageHeader.vue'
import { listarEventosAdmin } from '~/services/admin/eventos'
import type { AdminEventListItem } from '~/types/evento'
import { formatDataHora } from '~/utils/format'
import { classificarEventosVip, rotaVipEvento } from '~/utils/listaVip'

definePageMeta({
  title: 'Lista VIP',
  description: 'Gerencie os convidados VIP dos seus eventos.',
  layout: 'admin-layout',
  sidebarActive: 'Lista VIP',
  middleware: ['admin-auth']
})

const eventos = ref<AdminEventListItem[]>([])
const carregando = ref(true)
const erro = ref('')

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    eventos.value = await listarEventosAdmin()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os eventos.'
    eventos.value = []
  } finally {
    carregando.value = false
  }
}

onMounted(carregar)

const classificados = computed(() => classificarEventosVip(eventos.value))
const operacionais = computed(() => classificados.value.operacionais)
const historicos = computed(() => classificados.value.historicos)
const semEventos = computed(() => operacionais.value.length === 0 && historicos.value.length === 0)
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Lista VIP" subtitle="Gerencie os convidados VIP dos seus eventos." />

    <div v-if="carregando" class="space-y-3" aria-busy="true">
      <div v-for="n in 3" :key="n" class="h-24 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>

    <div
      v-else-if="erro"
      role="alert"
      class="space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
    >
      <p class="text-sm font-semibold text-red-300">{{ erro }}</p>
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
        @click="carregar"
      >
        Tentar novamente
      </button>
    </div>

    <BaseCard v-else-if="semEventos" class="space-y-4 text-center">
      <p class="text-sm text-zinc-400">Nenhum evento disponível para Lista VIP.</p>
      <AppButton variant="outline" to="/eventos">Ver eventos</AppButton>
    </BaseCard>

    <template v-else>
      <section v-if="operacionais.length > 0" class="space-y-3">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
          Próximos eventos
        </h2>
        <NuxtLink
          v-for="evento in operacionais"
          :key="evento.eventoId"
          :to="rotaVipEvento(evento.eventoId)"
          class="flex items-center justify-between gap-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-4 transition-colors duration-150 hover:border-amber-400/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        >
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <p class="truncate text-sm font-semibold text-white">{{ evento.nome }}</p>
              <EventStatusBadge :status="evento.status" />
            </div>
            <p class="mt-1 text-xs text-zinc-500">
              {{ formatDataHora(evento.inicioEm) }} · {{ evento.local }}
            </p>
          </div>
          <ChevronRightIcon class="h-5 w-5 shrink-0 text-zinc-600" />
        </NuxtLink>
      </section>

      <section v-if="historicos.length > 0" class="space-y-3">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
          Eventos realizados (consulta)
        </h2>
        <NuxtLink
          v-for="evento in historicos"
          :key="evento.eventoId"
          :to="rotaVipEvento(evento.eventoId)"
          class="flex items-center justify-between gap-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-4 transition-colors duration-150 hover:border-amber-400/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        >
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <p class="truncate text-sm font-semibold text-white">{{ evento.nome }}</p>
              <EventStatusBadge :status="evento.status" />
            </div>
            <p class="mt-1 text-xs text-zinc-500">
              {{ formatDataHora(evento.inicioEm) }} · {{ evento.local }}
            </p>
          </div>
          <ChevronRightIcon class="h-5 w-5 shrink-0 text-zinc-600" />
        </NuxtLink>
      </section>
    </template>
  </div>
</template>
