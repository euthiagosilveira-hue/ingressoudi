<script setup lang="ts">
import { computed } from 'vue'
import { PlusIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import PageHeader from '~/components/PageHeader.vue'
import EventEmptyState from '~/components/eventos/EventEmptyState.vue'
import EventFilters from '~/components/eventos/EventFilters.vue'
import EventGrid from '~/components/eventos/EventGrid.vue'
import { useAdminEvents } from '~/composables/useAdminEvents'

definePageMeta({
  title: 'Eventos',
  description: 'Gerencie seus eventos, vendas e ingressos.',
  layout: 'admin-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

const { filtros, eventosLista, carregando, erro, filtrosAtivos, carregar, refresh } =
  useAdminEvents()

const tituloVazio = computed(() =>
  filtrosAtivos.value ? 'Nenhum evento com os filtros selecionados' : 'Nenhum evento encontrado'
)
const subtituloVazio = computed(() =>
  filtrosAtivos.value
    ? 'Tente ajustar a busca ou os filtros.'
    : 'Crie seu primeiro evento para começar.'
)

function irParaCriar() {
  navigateTo('/eventos/novo')
}

function editarEvento(id: string) {
  navigateTo(`/eventos/${id}/editar`)
}

function acaoEvento(payload: { id: string; action: string }) {
  if (payload.action === 'lotes') {
    navigateTo(`/eventos/${payload.id}/lotes`)
    return
  }
  if (payload.action === 'vip') {
    navigateTo(`/eventos/${payload.id}/vip`)
    return
  }
  if (payload.action === 'editar') {
    editarEvento(payload.id)
    return
  }
  if (payload.action === 'visualizar') {
    const evento = eventosLista.value.find((item) => item.id === payload.id)
    if (evento) navigateTo(`/eventos/${evento.slug}`)
  }
}
</script>

<template>
  <PageHeader title="Eventos" subtitle="Gerencie seus eventos, vendas e ingressos.">
    <template #actions>
      <AppButton variant="primary" @click="irParaCriar">
        <PlusIcon class="h-4 w-4" />
        Criar evento
      </AppButton>
    </template>
  </PageHeader>

  <EventFilters v-model="filtros" />

  <!-- Loading -->
  <div v-if="carregando" class="mt-5 grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3" aria-busy="true">
    <div v-for="n in 3" :key="n" class="h-80 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
  </div>

  <!-- Erro -->
  <div
    v-else-if="erro"
    role="alert"
    class="mt-5 space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
  >
    <p class="text-sm font-semibold text-red-300">{{ erro }}</p>
    <button
      type="button"
      class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
      @click="refresh"
    >
      Tentar novamente
    </button>
  </div>

  <div v-else class="mt-5">
    <EventEmptyState
      v-if="eventosLista.length === 0"
      :title="tituloVazio"
      :subtitle="subtituloVazio"
      @create="irParaCriar"
    />

    <EventGrid
      v-else
      :events="eventosLista"
      @edit="editarEvento"
      @action="acaoEvento"
      @create="irParaCriar"
    />
  </div>

  <!-- Botao de refresh acessivel (revalida a lista) -->
  <div v-if="!carregando && !erro" class="mt-4 flex justify-center">
    <button
      type="button"
      class="text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
      @click="carregar"
    >
      Atualizar lista
    </button>
  </div>
</template>
