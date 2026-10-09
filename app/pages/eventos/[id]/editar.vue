<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'

import EventForm from '~/components/eventos/EventForm.vue'
import { atualizarEventoAdmin, obterEventoAdmin } from '~/services/admin/eventos'
import type { EventFormValue, EventPayload } from '~/types/evento'
import { mapearEventoAdminParaFormulario } from '~/utils/eventos'

definePageMeta({
  title: 'Editar evento',
  description: 'Atualize as informações do evento.',
  layout: 'admin-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

const route = useRoute()
const eventoId = String(route.params.id)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const carregando = ref(true)
const erro = ref('')
const valorInicial = ref<EventFormValue | null>(null)

async function carregar() {
  carregando.value = true
  erro.value = ''
  valorInicial.value = null

  if (!UUID.test(eventoId)) {
    erro.value = 'Evento não encontrado.'
    carregando.value = false
    return
  }

  try {
    const evento = await obterEventoAdmin(eventoId)
    valorInicial.value = mapearEventoAdminParaFormulario(evento)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o evento.'
  } finally {
    carregando.value = false
  }
}

async function aoSubmeter(payload: EventPayload) {
  try {
    await atualizarEventoAdmin(eventoId, {
      nome: payload.nome,
      slug: payload.slug,
      descricao: payload.descricao,
      imagemUrl: payload.imagemUrl,
      inicioEm: payload.inicioEm,
      local: payload.local,
      endereco: payload.endereco,
      capacidadeTotal: payload.capacidadeTotal,
      estoqueAntecipado: payload.estoqueAntecipado,
      publicacaoStatus: payload.publicacaoStatus,
      vendasStatus: payload.vendasStatus
    })
    toast.success('Evento atualizado com sucesso!')
    await navigateTo(`/eventos/${eventoId}/lotes`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar o evento.')
  }
}

function aoCancelar() {
  navigateTo(`/eventos/${eventoId}/lotes`)
}

onMounted(() => void carregar())
</script>

<template>
  <!-- Loading -->
  <div v-if="carregando" class="mx-auto w-full max-w-5xl space-y-6" aria-busy="true">
    <div class="h-10 w-56 animate-pulse rounded-xl border border-zinc-800 bg-zinc-900" />
    <div
      v-for="n in 4"
      :key="n"
      class="h-44 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900"
    />
  </div>

  <!-- Erro -->
  <div
    v-else-if="erro"
    role="alert"
    class="mx-auto max-w-xl space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
  >
    <p class="text-sm font-semibold text-red-300">{{ erro }}</p>
    <div class="flex flex-wrap items-center justify-center gap-3">
      <button
        type="button"
        class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
        @click="carregar"
      >
        Tentar novamente
      </button>
      <NuxtLink
        to="/eventos"
        class="text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
      >
        Voltar para eventos
      </NuxtLink>
    </div>
  </div>

  <EventForm
    v-else-if="valorInicial"
    mode="edit"
    :evento-id="eventoId"
    :initial-value="valorInicial"
    @submit="aoSubmeter"
    @cancel="aoCancelar"
  />
</template>
