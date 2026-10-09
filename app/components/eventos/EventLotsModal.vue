<script setup lang="ts">
import { computed, ref } from 'vue'
import { ArrowTopRightOnSquareIcon, PencilSquareIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import LotActivationBadge from '~/components/lotes/LotActivationBadge.vue'
import LotForm from '~/components/lotes/LotForm.vue'
import LotStatusBadge from '~/components/lotes/LotStatusBadge.vue'
import { useAdminLots } from '~/composables/useAdminLots'
import type { LotFormValue, LotListItem, LotPayload } from '~/types/lote'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import { ativacaoLoteBloqueada, eventoPermiteAbrirVendas, mapearLoteParaFormulario, proximaOrdem } from '~/utils/lotes'

const props = defineProps<{
  open: boolean
  eventoId: string
  eventoNome?: string
}>()

const emit = defineEmits<{
  close: []
}>()

const { evento, lotes, carregando, erro, processando, criar, atualizar, ativar, abrirVendas, refresh } =
  useAdminLots(props.eventoId)

const modo = ref<'lista' | 'novo' | 'editar'>('lista')
const loteEmEdicao = ref<LotListItem | null>(null)
const loteParaAtivar = ref<string | null>(null)

const lotesOrdenados = computed(() => [...lotes.value].sort((a, b) => a.ordem - b.ordem))
const vendasStatus = computed(() => evento.value?.vendasStatus ?? 'ENCERRADAS')
const podeAbrirVendas = computed(() =>
  evento.value ? eventoPermiteAbrirVendas(evento.value.status, evento.value.vendasStatus) : false
)
const valorInicialForm = computed<Partial<LotFormValue>>(() => ({
  ordem: proximaOrdem(lotes.value),
  tipoAtivacao: 'MANUAL',
  status: 'INATIVO'
}))
const valorInicialEdicao = computed<Partial<LotFormValue>>(() =>
  loteEmEdicao.value ? mapearLoteParaFormulario(loteEmEdicao.value) : {}
)
const ativacaoBloqueadaEdicao = computed(() => loteEmEdicao.value?.status === 'ATIVO')
const ordens = computed(() => lotes.value.map((lote) => ({ id: lote.id, ordem: lote.ordem })))
const loteAlvoAtivacao = computed(
  () => lotes.value.find((lote) => lote.id === loteParaAtivar.value) ?? null
)

function bloqueada(status: (typeof lotes.value)[number]['status']): boolean {
  return ativacaoLoteBloqueada(status, vendasStatus.value)
}

function fechar() {
  emit('close')
}

function abrirEdicao(loteId: string) {
  const lote = lotes.value.find((item) => item.id === loteId)
  if (!lote || lote.status === 'ENCERRADO') return
  loteEmEdicao.value = lote
  modo.value = 'editar'
}

function voltarLista() {
  loteEmEdicao.value = null
  modo.value = 'lista'
}

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
    modo.value = 'lista'
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível criar o lote.')
  }
}

async function aoAtualizar(payload: LotPayload) {
  const lote = loteEmEdicao.value
  if (!lote) return
  try {
    await atualizar(lote.id, {
      nome: payload.nome,
      quantidade: payload.quantidade,
      preco: payload.preco,
      tipoAtivacao: payload.tipoAtivacao,
      ativacaoEm: payload.ativacaoEm
    })
    toast.success('Lote atualizado com sucesso.')
    voltarLista()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível atualizar o lote.')
  }
}

function solicitarAtivacao(loteId: string) {
  const lote = lotes.value.find((item) => item.id === loteId)
  if (!lote) return
  if (ativacaoLoteBloqueada(lote.status, vendasStatus.value)) {
    toast.error('Abra as vendas do evento antes de ativar um lote.')
    return
  }
  loteParaAtivar.value = loteId
}

async function confirmarAtivacao() {
  const id = loteParaAtivar.value
  if (!id) return
  try {
    await ativar(id)
    toast.success('Lote ativado.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível ativar o lote.')
  } finally {
    loteParaAtivar.value = null
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
  <BaseModal
    :open="props.open"
    title="Lotes do evento"
    :subtitle="props.eventoNome || evento?.nome || ''"
    size="xl"
    @close="fechar"
  >
    <!-- Formulario de novo lote (reutiliza o LotForm real) -->
    <LotForm
      v-if="modo === 'novo'"
      mode="create"
      :initial-value="valorInicialForm"
      :ordens="ordens"
      :submitting="processando"
      @submit="aoCriar"
      @cancel="voltarLista"
    />

    <!-- Formulario de edicao (reutiliza o mesmo LotForm) -->
    <LotForm
      v-else-if="modo === 'editar'"
      mode="edit"
      :initial-value="valorInicialEdicao"
      :ordens="ordens"
      :id-atual="loteEmEdicao?.id ?? ''"
      :ativacao-bloqueada="ativacaoBloqueadaEdicao"
      :ordem-bloqueada="true"
      submit-label="Salvar alterações"
      :submitting="processando"
      @submit="aoAtualizar"
      @cancel="voltarLista"
    />

    <div v-else class="space-y-4">
      <!-- Vendas encerradas -->
      <div
        v-if="podeAbrirVendas"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-400/30 bg-amber-400/5 px-4 py-3"
      >
        <p class="text-xs text-amber-200">Abra as vendas do evento antes de ativar um lote.</p>
        <AppButton variant="outline" size="sm" :disabled="processando" @click="aoAbrirVendas">
          Abrir vendas
        </AppButton>
      </div>

      <!-- Loading -->
      <div v-if="carregando" class="space-y-3" aria-busy="true">
        <div v-for="n in 3" :key="n" class="h-24 animate-pulse rounded-xl border border-zinc-800 bg-zinc-950/60" />
      </div>

      <!-- Erro -->
      <div
        v-else-if="erro"
        role="alert"
        class="space-y-3 rounded-xl border border-red-500/40 bg-red-500/5 p-6 text-center"
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

      <!-- Vazio -->
      <div
        v-else-if="lotesOrdenados.length === 0"
        class="flex flex-col items-center justify-center rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-12 text-center"
      >
        <p class="text-base font-semibold text-white">Nenhum lote cadastrado</p>
        <p class="mt-1 text-sm text-zinc-500">
          Crie o primeiro lote para definir preço e quantidade de ingressos.
        </p>
        <AppButton variant="primary" class="mt-6" :disabled="processando" @click="modo = 'novo'">
          Novo lote
        </AppButton>
      </div>

      <!-- Lista -->
      <ul v-else class="space-y-3">
        <li
          v-for="lote in lotesOrdenados"
          :key="lote.id"
          class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="truncate text-base font-semibold text-white">{{ lote.nome }}</h3>
                <LotStatusBadge :status="lote.status" />
              </div>
              <p class="mt-0.5 text-xs text-zinc-500">{{ lote.ordem }}º lote</p>
            </div>
            <p class="text-lg font-bold text-amber-400">{{ formatMoeda(lote.preco) }}</p>
          </div>

          <div class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Quantidade</p>
              <p class="mt-0.5 text-sm font-semibold text-white">{{ formatNumero(lote.quantidade) }}</p>
            </div>
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Vendidos</p>
              <p class="mt-0.5 text-sm font-semibold text-white">{{ formatNumero(lote.vendidos) }}</p>
            </div>
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Disponíveis</p>
              <p class="mt-0.5 text-sm font-semibold text-white">{{ formatNumero(lote.disponiveis) }}</p>
            </div>
            <div>
              <p class="text-[11px] uppercase tracking-wide text-zinc-500">Ativação</p>
              <div class="mt-0.5"><LotActivationBadge :tipo="lote.tipoAtivacao" /></div>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap items-center justify-between gap-3 border-t border-zinc-800 pt-3">
            <div class="space-y-0.5 text-xs text-zinc-500">
              <p v-if="lote.ativacaoEm">Ativa em {{ formatDataHora(lote.ativacaoEm) }}</p>
              <p v-else-if="lote.ativadoEm">Ativado em {{ formatDataHora(lote.ativadoEm) }}</p>
              <p v-if="lote.encerradoEm">Encerrado em {{ formatDataHora(lote.encerradoEm) }}</p>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <button
                v-if="lote.status !== 'ENCERRADO'"
                type="button"
                class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-zinc-700 px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-zinc-200 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
                @click="abrirEdicao(lote.id)"
              >
                <PencilSquareIcon class="h-4 w-4" />
                Editar
              </button>

              <button
                v-if="lote.status === 'INATIVO'"
                type="button"
                :title="bloqueada(lote.status) ? 'Abra as vendas do evento antes de ativar um lote.' : undefined"
                :class="[
                  'inline-flex cursor-pointer items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold uppercase tracking-wide transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50',
                  bloqueada(lote.status)
                    ? 'cursor-not-allowed border-zinc-700 text-zinc-500'
                    : 'border-green-500/40 bg-green-500/10 text-green-300 hover:bg-green-500/20'
                ]"
                @click="solicitarAtivacao(lote.id)"
              >
                Ativar lote
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>

    <template #footer>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <NuxtLink
          :to="`/eventos/${props.eventoId}/lotes`"
          class="inline-flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
        >
          <ArrowTopRightOnSquareIcon class="h-4 w-4" />
          Ver gestão completa de lotes
        </NuxtLink>

        <div class="flex items-center gap-3">
          <AppButton
            v-if="modo === 'lista'"
            variant="primary"
            :disabled="processando"
            @click="modo = 'novo'"
          >
            <PlusIcon class="h-4 w-4" />
            Novo lote
          </AppButton>
          <AppButton variant="ghost" @click="fechar">Fechar</AppButton>
        </div>
      </div>
    </template>
  </BaseModal>

  <ConfirmDialog
    :open="loteParaAtivar !== null"
    :title="`Ativar ${loteAlvoAtivacao?.nome ?? ''}?`"
    description="O lote atualmente ativo será encerrado e este passará a ser o lote vigente."
    confirm-label="Ativar lote"
    @confirm="confirmarAtivacao"
    @cancel="loteParaAtivar = null"
  />
</template>
