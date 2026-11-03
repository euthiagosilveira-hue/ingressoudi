<script setup lang="ts">
import { toast } from 'vue3-toastify'

import EventMeiaCard from '~/components/eventos/EventMeiaCard.vue'
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
  setores,
  carregando,
  erro,
  processando,
  criar,
  atualizar,
  ativar,
  encerrar,
  abrirVendas,
  criarSetor,
  renomearSetor,
  excluirSetor,
  refresh
} = useAdminLots(String(route.params.id))

async function aoCriar(payload: LotPayload) {
  try {
    await criar({
      nome: payload.nome,
      quantidade: payload.quantidade,
      preco: payload.preco,
      tipoAtivacao: payload.tipoAtivacao,
      ativacaoEm: payload.ativacaoEm,
      setorId: payload.setorId
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

async function aoEncerrar(id: string, ativarProximo: boolean) {
  try {
    const r = await encerrar(id, ativarProximo)
    toast.success(r.loteAtivadoNome ? `Lote encerrado. ${r.loteAtivadoNome} ativado.` : 'Lote encerrado.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível encerrar o lote.')
  }
}

async function acaoSetor(acao: () => Promise<void>, sucesso: string, falha: string) {
  try {
    await acao()
    toast.success(sucesso)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : falha)
  }
}

const aoCriarSetor = (nome: string) =>
  acaoSetor(() => criarSetor(nome), `Setor ${nome} criado.`, 'Não foi possível criar o setor.')
const aoRenomearSetor = (id: string, nome: string) =>
  acaoSetor(() => renomearSetor(id, nome), 'Setor renomeado.', 'Não foi possível renomear o setor.')
const aoExcluirSetor = (id: string) =>
  acaoSetor(() => excluirSetor(id), 'Setor excluído.', 'Não foi possível excluir o setor.')

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

  <div v-else-if="evento" class="space-y-6">
    <LotManager
      :evento="evento"
      :lotes="lotes"
      :estoque-antecipado="estoqueAntecipado"
      :setores="setores"
      :processando="processando"
      @criar="aoCriar"
      @atualizar="aoAtualizar"
      @ativar="aoAtivar"
      @encerrar="aoEncerrar"
      @abrir-vendas="aoAbrirVendas"
      @criar-setor="aoCriarSetor"
      @renomear-setor="aoRenomearSetor"
      @excluir-setor="aoExcluirSetor"
    />
    <EventMeiaCard :evento-id="String(route.params.id)" />
  </div>

  <LotEventNotFound v-else />
</template>
