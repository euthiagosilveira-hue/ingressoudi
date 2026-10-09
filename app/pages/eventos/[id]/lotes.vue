<script setup lang="ts">
import { toast } from 'vue3-toastify'

import LotEventNotFound from '~/components/lotes/LotEventNotFound.vue'
import LotManager from '~/components/lotes/LotManager.vue'
import { useAdminLots } from '~/composables/useAdminLots'
import type { LotPayload } from '~/types/lote'

definePageMeta({
  title: 'Lotes',
  description: 'Gerencie os preços e as etapas de venda deste evento.',
  layout: 'admin-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

const route = useRoute()
const {
  evento,
  estoqueAntecipado,
  lotes,
  carregando,
  erro,
  processando,
  criar,
  atualizar,
  ativar,
  abrirVendas,
  refresh
} = useAdminLots(String(route.params.id))

async function aoCriar(payload: LotPayload) {
  try {
    await criar({
      nome: payload.nome,
      quantidade: payload.quantidade,
      preco: payload.preco,
      tipoAtivacao: payload.tipoAtivacao,
      ativacaoEm: payload.ativacaoEm
    })
    toast.success('Lote criado com sucesso!')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível criar o lote.')
  }
}

async function aoAtualizar(id: string, payload: LotPayload) {
  try {
    await atualizar(id, {
      nome: payload.nome,
      quantidade: payload.quantidade,
      preco: payload.preco,
      tipoAtivacao: payload.tipoAtivacao,
      ativacaoEm: payload.ativacaoEm
    })
    toast.success('Lote atualizado com sucesso.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar o lote.')
  }
}

async function aoAtivar(id: string) {
  try {
    await ativar(id)
    toast.success('Lote ativado.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível ativar o lote.')
  }
}

async function aoAbrirVendas() {
  try {
    await abrirVendas()
    toast.success('Vendas abertas.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível abrir as vendas.')
  }
}
</script>

<template>
  <!-- Loading -->
  <div v-if="carregando" class="space-y-6" aria-busy="true">
    <div class="h-32 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    <div class="grid grid-cols-1 gap-5 lg:grid-cols-2 xl:grid-cols-3">
      <div v-for="n in 3" :key="n" class="h-64 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>
  </div>

  <!-- Erro -->
  <div
    v-else-if="erro"
    role="alert"
    class="mx-auto max-w-xl space-y-3 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center"
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

  <LotManager
    v-else-if="evento"
    :evento="evento"
    :lotes="lotes"
    :estoque-antecipado="estoqueAntecipado"
    :processando="processando"
    @criar="aoCriar"
    @atualizar="aoAtualizar"
    @ativar="aoAtivar"
    @abrir-vendas="aoAbrirVendas"
  />

  <LotEventNotFound v-else />
</template>
