<script setup lang="ts">
import { computed, ref } from 'vue'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import PageHeader from '~/components/PageHeader.vue'
import EntryCancelModal from '~/components/entradas/EntryCancelModal.vue'
import EntryDetailsModal from '~/components/entradas/EntryDetailsModal.vue'
import EntryEmptyState from '~/components/entradas/EntryEmptyState.vue'
import EntryFilters from '~/components/entradas/EntryFilters.vue'
import EntryMobileList from '~/components/entradas/EntryMobileList.vue'
import EntryPagination from '~/components/entradas/EntryPagination.vue'
import EntrySummary from '~/components/entradas/EntrySummary.vue'
import EntryTable from '~/components/entradas/EntryTable.vue'
import { useAdminEntries } from '~/composables/useAdminEntries'
import type { SelectOption } from '~/types/ui'
import type { EntryFiltersState, EntryListItem, EntrySort } from '~/types/entrada'

const {
  itens,
  filtros,
  ordenacao,
  pagina,
  entradasPaginadas,
  total,
  numeroPaginas,
  resumo,
  temFiltros,
  limparFiltros,
  irPara,
  eventoOptions
} = useAdminEntries(10)

const sortOptions: SelectOption[] = [
  { value: 'RECENTES', label: 'Mais recentes' },
  { value: 'ANTIGAS', label: 'Mais antigas' },
  { value: 'PARTICIPANTE_AZ', label: 'Participante A–Z' }
]

const ordenacaoSelecionada = computed({
  get: () => ordenacao.value,
  set: (valor: string) => {
    ordenacao.value = valor as EntrySort
  }
})

const detalhesAbertos = ref(false)
const entradaDetalhes = ref<EntryListItem | null>(null)
const anulacaoAberta = ref(false)
const entradaAnulacao = ref<EntryListItem | null>(null)

function atualizarFiltros(valor: EntryFiltersState) {
  Object.assign(filtros, valor)
}

function abrirDetalhes(id: string) {
  const entrada = itens.value.find((item) => item.id === id) ?? null
  if (!entrada) return
  entradaDetalhes.value = entrada
  detalhesAbertos.value = true
}

function acaoEntrada(payload: {
  id: string
  ingressoId: string
  pedidoId: string
  action: string
}) {
  if (payload.action === 'ingresso') {
    navigateTo(`/ingressos/${payload.ingressoId}`)
    return
  }

  if (payload.action === 'pedido') {
    navigateTo(`/pedidos/${payload.pedidoId}`)
    return
  }

  if (payload.action === 'anular') {
    const entrada = itens.value.find((item) => item.id === payload.id) ?? null
    if (!entrada || entrada.anuladaEm) return
    entradaAnulacao.value = entrada
    anulacaoAberta.value = true
    return
  }

  abrirDetalhes(payload.id)
}

function confirmarAnulacao(_motivo: string) {
  const alvo = entradaAnulacao.value
  if (!alvo) return

  // Somente leitura nesta etapa: a anulacao real sera implementada depois.
  toast.info('Ação de anulação disponível em etapa futura.')

  anulacaoAberta.value = false
  entradaAnulacao.value = null
}

function irParaPortaria() {
  navigateTo('/portaria')
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Entradas" subtitle="Consulte e audite os acessos registrados nos eventos.">
      <template #actions>
        <AppButton variant="outline" @click="irParaPortaria">Ir para Portaria</AppButton>
      </template>
    </PageHeader>

    <EntrySummary :resumo="resumo" />

    <EntryFilters :model-value="filtros" :eventos="eventoOptions" @update:model-value="atualizarFiltros" />

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">
        {{ total }}
        {{ total === 1 ? 'entrada encontrada' : 'entradas encontradas' }}
      </p>

      <div class="w-full sm:w-48">
        <BaseSelect v-model="ordenacaoSelecionada" :options="sortOptions" />
      </div>
    </div>

    <EntryEmptyState
      v-if="total === 0"
      :tem-filtros="temFiltros"
      @limpar="limparFiltros"
    />

    <template v-else>
      <div class="hidden lg:block">
        <EntryTable :entradas="entradasPaginadas" @action="acaoEntrada" />
      </div>

      <div class="lg:hidden">
        <EntryMobileList :entradas="entradasPaginadas" @action="acaoEntrada" />
      </div>

      <EntryPagination
        v-if="numeroPaginas > 1"
        :pagina="pagina"
        :total-paginas="numeroPaginas"
        @ir="irPara"
      />
    </template>

    <EntryDetailsModal
      :open="detalhesAbertos"
      :entrada="entradaDetalhes"
      @close="detalhesAbertos = false"
    />

    <EntryCancelModal
      :open="anulacaoAberta"
      :entrada="entradaAnulacao"
      @confirm="confirmarAnulacao"
      @cancel="anulacaoAberta = false"
    />
  </div>
</template>
