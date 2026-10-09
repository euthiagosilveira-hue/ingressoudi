<script setup lang="ts">
import { toast } from 'vue3-toastify'

import VipManager from '~/components/vip/VipManager.vue'
import { useAdminVip } from '~/composables/useAdminVip'
import type { VipPayload } from '~/types/vip'

definePageMeta({
  title: 'Lista VIP',
  description: 'Gerencie os convidados com acesso liberado para este evento.',
  layout: 'admin-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

const route = useRoute()
const { eventoNome, vips, carregando, erro, processando, criar, criarLote, atualizar, remover, refresh } =
  useAdminVip(String(route.params.id))

async function aoCriar(payload: VipPayload) {
  try {
    await criar(payload)
    toast.success('Convidado adicionado à lista VIP.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível adicionar o convidado.')
  }
}

async function aoCriarLote(nomes: string[]) {
  try {
    const quantidade = await criarLote(nomes)
    toast.success(`${quantidade} convidado${quantidade === 1 ? '' : 's'} adicionado${quantidade === 1 ? '' : 's'} à Lista VIP.`)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível adicionar os convidados.')
  }
}

async function aoAtualizar(vipId: string, payload: VipPayload) {
  try {
    await atualizar(vipId, payload)
    toast.success('Convidado atualizado.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar o convidado.')
  }
}

async function aoRemover(vipId: string) {
  try {
    await remover(vipId)
    toast.success('Convidado removido da lista VIP.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível remover o convidado.')
  }
}
</script>

<template>
  <div v-if="carregando" class="space-y-6" aria-busy="true">
    <div class="h-8 w-48 animate-pulse rounded-lg bg-zinc-800" />
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <div v-for="n in 3" :key="n" class="h-24 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>
    <div class="h-64 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
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
      @click="refresh"
    >
      Tentar novamente
    </button>
  </div>

  <VipManager
    v-else
    :evento-nome="eventoNome"
    :vips="vips"
    :processando="processando"
    @criar="aoCriar"
    @criar-lote="aoCriarLote"
    @atualizar="aoAtualizar"
    @remover="aoRemover"
  />
</template>
