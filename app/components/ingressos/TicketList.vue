<script setup lang="ts">
import { computed } from 'vue'

import BaseSelect from '~/components/BaseSelect.vue'
import PageHeader from '~/components/PageHeader.vue'
import TicketEmptyState from '~/components/ingressos/TicketEmptyState.vue'
import TicketFilters from '~/components/ingressos/TicketFilters.vue'
import TicketMobileList from '~/components/ingressos/TicketMobileList.vue'
import TicketPagination from '~/components/ingressos/TicketPagination.vue'
import TicketSummary from '~/components/ingressos/TicketSummary.vue'
import TicketTable from '~/components/ingressos/TicketTable.vue'
import { useAdminTickets } from '~/composables/useAdminTickets'
import type { SelectOption } from '~/types/ui'
import type { TicketFiltersState, TicketSort } from '~/types/ingresso'

const {
  filtros,
  ordenacao,
  pagina,
  ingressosPaginados,
  total,
  numeroPaginas,
  resumo,
  temFiltros,
  limparFiltros,
  irPara,
  eventoOptions
} = useAdminTickets(10)

const sortOptions: SelectOption[] = [
  { value: 'RECENTES', label: 'Mais recentes' },
  { value: 'ANTIGOS', label: 'Mais antigos' },
  { value: 'PARTICIPANTE_AZ', label: 'Participante A–Z' }
]

const ordenacaoSelecionada = computed({
  get: () => ordenacao.value,
  set: (valor: string) => {
    ordenacao.value = valor as TicketSort
  }
})

function atualizarFiltros(valor: TicketFiltersState) {
  Object.assign(filtros, valor)
}

function acaoIngresso(payload: {
  id: string
  pedidoId: string
  eventoId: string
  action: string
}) {
  if (payload.action === 'ver-pedido') {
    navigateTo(`/pedidos/${payload.pedidoId}`)
    return
  }

  if (payload.action === 'ver-evento') {
    navigateTo(`/eventos/${payload.eventoId}/lotes`)
    return
  }

  navigateTo(`/ingressos/${payload.id}`)
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Ingressos"
      subtitle="Consulte ingressos emitidos, status e utilização nos eventos."
    />

    <TicketSummary :resumo="resumo" />

    <TicketFilters :model-value="filtros" :eventos="eventoOptions" @update:model-value="atualizarFiltros" />

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">
        {{ total }}
        {{ total === 1 ? 'ingresso encontrado' : 'ingressos encontrados' }}
      </p>

      <div class="w-full sm:w-48">
        <BaseSelect v-model="ordenacaoSelecionada" :options="sortOptions" />
      </div>
    </div>

    <TicketEmptyState
      v-if="total === 0"
      :tem-filtros="temFiltros"
      @limpar="limparFiltros"
    />

    <template v-else>
      <div class="hidden lg:block">
        <TicketTable :ingressos="ingressosPaginados" @action="acaoIngresso" />
      </div>

      <div class="lg:hidden">
        <TicketMobileList :ingressos="ingressosPaginados" @action="acaoIngresso" />
      </div>

      <TicketPagination
        v-if="numeroPaginas > 1"
        :pagina="pagina"
        :total-paginas="numeroPaginas"
        @ir="irPara"
      />
    </template>
  </div>
</template>
