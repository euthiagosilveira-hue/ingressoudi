<script setup lang="ts">
import { toast } from 'vue3-toastify'

import EventForm from '~/components/eventos/EventForm.vue'
import { criarEventoAdmin } from '~/services/admin/eventos'
import type { EventPayload } from '~/types/evento'

definePageMeta({
  title: 'Criar evento',
  description: 'Preencha as informações do seu evento.',
  layout: 'admin-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

async function aoSubmeter(payload: EventPayload) {
  try {
    const evento = await criarEventoAdmin({
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
    toast.success('Evento criado com sucesso!')
    await navigateTo(`/eventos/${evento.eventoId}/lotes`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível criar o evento.')
  }
}

function aoCancelar() {
  navigateTo('/eventos')
}
</script>

<template>
  <EventForm mode="create" @submit="aoSubmeter" @cancel="aoCancelar" />
</template>
