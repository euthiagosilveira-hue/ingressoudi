<script setup lang="ts">
import { onMounted, ref } from 'vue'

import GateApp from '~/components/portaria/GateApp.vue'
import { listarEventosPortaria } from '~/services/gate/eventos'
import type { EventListItem } from '~/types/evento'
import type { EventoPortaria } from '~/types/gate'

definePageMeta({
  title: 'Portaria',
  description: 'Valide ingressos e registre entradas do evento.',
  layout: 'admin-layout',
  sidebarActive: 'Portaria',
  middleware: ['operator-auth']
})

const eventos = ref<EventListItem[]>([])
const carregando = ref(true)
const erro = ref('')

function mapearEvento(evento: EventoPortaria): EventListItem {
  return {
    id: evento.eventoId,
    nome: evento.nome,
    slug: '',
    imagemUrl: null,
    inicioEm: evento.inicioEm,
    local: evento.local,
    status: evento.status as EventListItem['status'],
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    loteAtual: null,
    vendidos: 0,
    disponiveis: 0
  }
}

async function carregarEventos() {
  carregando.value = true
  erro.value = ''
  try {
    const lista = await listarEventosPortaria()
    eventos.value = lista.map(mapearEvento)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os eventos.'
  } finally {
    carregando.value = false
  }
}

onMounted(() => {
  void carregarEventos()
})
</script>

<template>
  <div class="pb-[env(safe-area-inset-bottom)]">
    <p
      v-if="carregando"
      class="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 text-center text-sm text-zinc-400"
    >
      Carregando eventos...
    </p>

    <div
      v-else-if="erro"
      role="alert"
      class="space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
    >
      <p class="text-sm font-semibold text-red-300">{{ erro }}</p>
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
        @click="carregarEventos"
      >
        Tentar novamente
      </button>
    </div>

    <GateApp v-else :eventos="eventos" />
  </div>
</template>
