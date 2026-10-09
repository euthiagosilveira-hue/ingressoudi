<script setup lang="ts">
import { computed, ref } from 'vue'
import { ArrowLeftIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import PageHeader from '~/components/PageHeader.vue'
import LotDetailsModal from '~/components/lotes/LotDetailsModal.vue'
import LotEventHeader from '~/components/lotes/LotEventHeader.vue'
import LotFormModal from '~/components/lotes/LotFormModal.vue'
import LotGrid from '~/components/lotes/LotGrid.vue'
import type { EventListItem } from '~/types/evento'
import type {
  LotFormMode,
  LotFormValue,
  LotListItem,
  LotOrdemRef,
  LotPayload
} from '~/types/lote'
import { mapearLoteParaFormulario, proximaOrdem } from '~/utils/lotes'

const props = defineProps<{
  evento: EventListItem
  lotes: LotListItem[]
  estoqueAntecipado: number
  processando?: boolean
}>()

const emit = defineEmits<{
  criar: [payload: LotPayload]
  atualizar: [id: string, payload: LotPayload]
  ativar: [id: string]
  abrirVendas: []
}>()

const vendasAbertas = computed(() => props.evento.vendasStatus === 'ABERTAS')

const formAberto = ref(false)
const formModo = ref<LotFormMode>('create')
const loteEmEdicao = ref<LotListItem | null>(null)

const loteParaAtivar = ref<LotListItem | null>(null)
const loteParaEncerrar = ref<LotListItem | null>(null)
const loteDetalhes = ref<LotListItem | null>(null)

const lotesOrdenados = computed(() => [...props.lotes].sort((a, b) => a.ordem - b.ordem))
const ordens = computed<LotOrdemRef[]>(() =>
  props.lotes.map((lote) => ({ id: lote.id, ordem: lote.ordem }))
)
const totalLotes = computed(() => props.lotes.length)
const lotesAtivos = computed(() => props.lotes.filter((lote) => lote.status === 'ATIVO').length)
const vendidos = computed(() => props.lotes.reduce((total, lote) => total + lote.vendidos, 0))
const disponiveis = computed(() => props.lotes.reduce((total, lote) => total + lote.disponiveis, 0))
const precoAtual = computed(() => {
  const ativo = props.lotes.find((lote) => lote.status === 'ATIVO')
  return ativo ? ativo.preco : null
})

const valorInicialForm = computed<Partial<LotFormValue>>(() => {
  if (formModo.value === 'edit' && loteEmEdicao.value) {
    return mapearLoteParaFormulario(loteEmEdicao.value)
  }
  return {
    ordem: proximaOrdem(props.lotes),
    tipoAtivacao: 'MANUAL',
    status: 'INATIVO'
  }
})

function abrirNovo() {
  formModo.value = 'create'
  loteEmEdicao.value = null
  formAberto.value = true
}

function abrirEdicao(id: string) {
  const lote = props.lotes.find((item) => item.id === id)
  if (!lote) return
  formModo.value = 'edit'
  loteEmEdicao.value = lote
  formAberto.value = true
}

function fecharForm() {
  formAberto.value = false
  loteEmEdicao.value = null
}

function salvar(payload: LotPayload) {
  if (formModo.value === 'create') {
    emit('criar', payload)
  } else if (loteEmEdicao.value) {
    emit('atualizar', loteEmEdicao.value.id, payload)
  }
  fecharForm()
}

function solicitarAtivacao(id: string) {
  loteParaAtivar.value = props.lotes.find((item) => item.id === id) ?? null
}

function confirmarAtivacao() {
  const alvo = loteParaAtivar.value
  if (!alvo) return
  emit('ativar', alvo.id)
  loteParaAtivar.value = null
}

function solicitarEncerramento(id: string) {
  loteParaEncerrar.value = props.lotes.find((item) => item.id === id) ?? null
}

function confirmarEncerramento() {
  const alvo = loteParaEncerrar.value
  if (!alvo) return
  toast.info('O encerramento ocorre automaticamente na virada do lote.')
  loteParaEncerrar.value = null
}

function acaoLote(payload: { id: string; action: string }) {
  switch (payload.action) {
    case 'editar':
      abrirEdicao(payload.id)
      break
    case 'ativar':
      solicitarAtivacao(payload.id)
      break
    case 'ativar-bloqueado':
      toast.error('Abra as vendas do evento antes de ativar um lote.')
      break
    case 'encerrar':
      solicitarEncerramento(payload.id)
      break
    case 'detalhes':
      loteDetalhes.value = props.lotes.find((item) => item.id === payload.id) ?? null
      break
  }
}
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-3">
      <NuxtLink
        to="/eventos"
        class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        <ArrowLeftIcon class="h-4 w-4" />
        Voltar para eventos
      </NuxtLink>

      <nav class="flex flex-wrap items-center gap-1.5 text-xs text-zinc-500" aria-label="Breadcrumb">
        <NuxtLink to="/eventos" class="transition-colors hover:text-zinc-300">Eventos</NuxtLink>
        <span aria-hidden="true">/</span>
        <span class="max-w-[12rem] truncate text-zinc-400">{{ props.evento.nome }}</span>
        <span aria-hidden="true">/</span>
        <span class="text-zinc-400">Lotes</span>
      </nav>
    </div>

    <PageHeader title="Lotes" subtitle="Gerencie os preços e as etapas de venda deste evento.">
      <template #actions>
        <AppButton variant="primary" :disabled="props.processando" @click="abrirNovo">
          <PlusIcon class="h-4 w-4" />
          Novo lote
        </AppButton>
      </template>
    </PageHeader>

    <LotEventHeader
      :evento="props.evento"
      :estoque-antecipado="props.estoqueAntecipado"
      :vendidos="vendidos"
      :disponiveis="disponiveis"
      :total-lotes="totalLotes"
      :lotes-ativos="lotesAtivos"
      :preco-atual="precoAtual"
      :vendas-status="props.evento.vendasStatus"
      @abrir-vendas="emit('abrirVendas')"
    />

    <LotGrid :lotes="lotesOrdenados" :vendas-abertas="vendasAbertas" @action="acaoLote" @create="abrirNovo" />

    <LotFormModal
      :open="formAberto"
      :mode="formModo"
      :initial-value="valorInicialForm"
      :ordens="ordens"
      :id-atual="loteEmEdicao?.id ?? ''"
      :ativacao-bloqueada="formModo === 'edit' && loteEmEdicao?.status === 'ATIVO'"
      :ordem-bloqueada="formModo === 'edit'"
      :submit-label="formModo === 'edit' ? 'Salvar alterações' : 'Salvar lote'"
      :submitting="props.processando"
      @submit="salvar"
      @cancel="fecharForm"
    />

    <LotDetailsModal
      :open="loteDetalhes !== null"
      :lote="loteDetalhes"
      @close="loteDetalhes = null"
    />

    <ConfirmDialog
      :open="loteParaAtivar !== null"
      :title="`Ativar ${loteParaAtivar?.nome ?? ''}?`"
      description="O lote atualmente ativo será encerrado e este passará a ser o lote vigente."
      confirm-label="Ativar lote"
      @confirm="confirmarAtivacao"
      @cancel="loteParaAtivar = null"
    />

    <ConfirmDialog
      :open="loteParaEncerrar !== null"
      tone="danger"
      :title="`Encerrar ${loteParaEncerrar?.nome ?? ''}?`"
      description="O lote será encerrado e não poderá ser reaberto."
      confirm-label="Encerrar lote"
      @confirm="confirmarEncerramento"
      @cancel="loteParaEncerrar = null"
    />
  </div>
</template>
