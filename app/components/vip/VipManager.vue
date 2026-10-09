<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  ArrowLeftIcon,
  ClipboardDocumentListIcon,
  PencilSquareIcon,
  PlusIcon,
  TrashIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import PageHeader from '~/components/PageHeader.vue'
import VipBulkAddModal from '~/components/vip/VipBulkAddModal.vue'
import VipFormModal from '~/components/vip/VipFormModal.vue'
import VipStatusBadge from '~/components/vip/VipStatusBadge.vue'
import type { VipConvidado, VipFormValue, VipPayload } from '~/types/vip'
import { formatDataHora } from '~/utils/format'
import { filtrarVips, resumoVips, statusVip } from '~/utils/vip'

const props = withDefaults(
  defineProps<{
    eventoNome: string
    vips: VipConvidado[]
    processando?: boolean
  }>(),
  { processando: false }
)

const emit = defineEmits<{
  criar: [payload: VipPayload]
  criarLote: [nomes: string[]]
  atualizar: [vipId: string, payload: VipPayload]
  remover: [vipId: string]
}>()

const busca = ref('')
const formAberto = ref(false)
const bulkAberto = ref(false)
const formModo = ref<'create' | 'edit'>('create')
const vipEmEdicao = ref<VipConvidado | null>(null)
const vipParaRemover = ref<VipConvidado | null>(null)

const vipsFiltrados = computed(() => filtrarVips(props.vips, busca.value))
const resumo = computed(() => resumoVips(props.vips))

const valorInicialForm = computed<VipFormValue | null>(() =>
  vipEmEdicao.value
    ? {
        nome: vipEmEdicao.value.nome,
        telefone: vipEmEdicao.value.telefone ?? '',
        observacao: vipEmEdicao.value.observacao ?? ''
      }
    : null
)

function abrirNovo() {
  formModo.value = 'create'
  vipEmEdicao.value = null
  formAberto.value = true
}

function abrirBulk() {
  bulkAberto.value = true
}

function salvarLote(nomes: string[]) {
  emit('criarLote', nomes)
  bulkAberto.value = false
}

function abrirEdicao(vip: VipConvidado) {
  formModo.value = 'edit'
  vipEmEdicao.value = vip
  formAberto.value = true
}

function fecharForm() {
  formAberto.value = false
  vipEmEdicao.value = null
}

function salvar(payload: VipPayload) {
  if (formModo.value === 'edit' && vipEmEdicao.value) {
    emit('atualizar', vipEmEdicao.value.vipId, payload)
  } else {
    emit('criar', payload)
  }
  fecharForm()
}

function solicitarRemocao(vip: VipConvidado) {
  vipParaRemover.value = vip
}

function confirmarRemocao() {
  if (vipParaRemover.value) emit('remover', vipParaRemover.value.vipId)
  vipParaRemover.value = null
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
        <span class="max-w-[12rem] truncate text-zinc-400">{{ props.eventoNome }}</span>
        <span aria-hidden="true">/</span>
        <span class="text-zinc-400">Lista VIP</span>
      </nav>
    </div>

    <PageHeader
      title="Lista VIP"
      subtitle="Gerencie os convidados com acesso liberado para este evento."
    >
      <template #actions>
        <AppButton variant="outline" :disabled="props.processando" @click="abrirBulk">
          <ClipboardDocumentListIcon class="h-4 w-4" />
          Adicionar vários
        </AppButton>
        <AppButton variant="primary" :disabled="props.processando" @click="abrirNovo">
          <PlusIcon class="h-4 w-4" />
          Adicionar à lista VIP
        </AppButton>
      </template>
    </PageHeader>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <BaseCard>
        <p class="text-[11px] uppercase tracking-wide text-zinc-500">Convidados</p>
        <p class="mt-1 text-2xl font-bold text-white">{{ resumo.total }}</p>
      </BaseCard>
      <BaseCard>
        <p class="text-[11px] uppercase tracking-wide text-zinc-500">Aguardando</p>
        <p class="mt-1 text-2xl font-bold text-amber-300">{{ resumo.aguardando }}</p>
      </BaseCard>
      <BaseCard>
        <p class="text-[11px] uppercase tracking-wide text-zinc-500">Entraram</p>
        <p class="mt-1 text-2xl font-bold text-green-300">{{ resumo.entraram }}</p>
      </BaseCard>
    </div>

    <BaseCard class="space-y-4">
      <BaseInput v-model="busca" label="Buscar" placeholder="Buscar por nome ou telefone" />

      <div
        v-if="vipsFiltrados.length === 0"
        class="rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 p-8 text-center"
      >
        <p class="text-sm text-zinc-400">
          {{
            props.vips.length === 0
              ? 'Nenhum convidado na lista VIP ainda.'
              : 'Nenhum convidado corresponde à busca.'
          }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="vip in vipsFiltrados"
          :key="vip.vipId"
          class="flex flex-col gap-3 rounded-2xl border border-zinc-800 bg-zinc-950/40 p-4 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="min-w-0">
            <p class="truncate text-sm font-semibold text-white">{{ vip.nome }}</p>
            <p v-if="vip.telefone" class="text-xs text-zinc-500">{{ vip.telefone }}</p>
            <p v-if="vip.observacao" class="mt-1 text-xs text-zinc-500">{{ vip.observacao }}</p>
            <div class="mt-2 flex flex-wrap items-center gap-2">
              <VipStatusBadge :status="statusVip(vip)" />
              <span v-if="vip.entradaEm" class="text-[11px] text-zinc-500">
                Entrada registrada às {{ formatDataHora(vip.entradaEm) }}
              </span>
            </div>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <template v-if="!vip.entrou">
              <AppButton variant="outline" size="sm" @click="abrirEdicao(vip)">
                <PencilSquareIcon class="h-4 w-4" />
                Editar
              </AppButton>
              <AppButton variant="danger" size="sm" @click="solicitarRemocao(vip)">
                <TrashIcon class="h-4 w-4" />
                Remover
              </AppButton>
            </template>
            <span v-else class="text-[11px] text-zinc-500">Histórico preservado</span>
          </div>
        </div>
      </div>
    </BaseCard>

    <VipFormModal
      :open="formAberto"
      :mode="formModo"
      :initial-value="valorInicialForm"
      :submitting="props.processando"
      @submit="salvar"
      @cancel="fecharForm"
    />

    <VipBulkAddModal
      :open="bulkAberto"
      :submitting="props.processando"
      @submit="salvarLote"
      @cancel="bulkAberto = false"
    />

    <ConfirmDialog
      :open="vipParaRemover !== null"
      tone="danger"
      :title="`Remover ${vipParaRemover?.nome ?? ''} da lista VIP?`"
      description="O convidado será removido da lista. Esta ação só é possível antes da entrada."
      confirm-label="Remover"
      @confirm="confirmarRemocao"
      @cancel="vipParaRemover = null"
    />
  </div>
</template>
