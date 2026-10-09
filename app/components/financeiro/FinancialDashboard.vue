<script setup lang="ts">
import { computed, ref } from 'vue'

import BaseSelect from '~/components/BaseSelect.vue'
import PageHeader from '~/components/PageHeader.vue'
import FinancialSummary from '~/components/financeiro/FinancialSummary.vue'
import PaymentDetailsModal from '~/components/financeiro/PaymentDetailsModal.vue'
import PaymentEmptyState from '~/components/financeiro/PaymentEmptyState.vue'
import PaymentFilters from '~/components/financeiro/PaymentFilters.vue'
import PaymentMobileList from '~/components/financeiro/PaymentMobileList.vue'
import PaymentPagination from '~/components/financeiro/PaymentPagination.vue'
import PaymentTable from '~/components/financeiro/PaymentTable.vue'
import { useAdminFinance } from '~/composables/useAdminFinance'
import type { SelectOption } from '~/types/ui'
import type {
  FinancialFiltersState,
  FinancialSort,
  PaymentListItem
} from '~/types/pagamento'

const {
  filtros,
  ordenacao,
  pagina,
  pagamentos,
  pagamentosPaginados,
  total,
  numeroPaginas,
  resumo,
  temFiltros,
  limparFiltros,
  irPara,
  eventoOptions
} = useAdminFinance(10)

const sortOptions: SelectOption[] = [
  { value: 'RECENTES', label: 'Mais recentes' },
  { value: 'ANTIGOS', label: 'Mais antigos' },
  { value: 'MAIOR_VALOR', label: 'Maior valor' },
  { value: 'MENOR_VALOR', label: 'Menor valor' }
]

const ordenacaoSelecionada = computed({
  get: () => ordenacao.value,
  set: (valor: string) => {
    ordenacao.value = valor as FinancialSort
  }
})

const detalhesAbertos = ref(false)
const pagamentoDetalhes = ref<PaymentListItem | null>(null)

function atualizarFiltros(valor: FinancialFiltersState) {
  Object.assign(filtros, valor)
}

function acaoPagamento(payload: { id: string; pedidoId: string; action: string }) {
  if (payload.action === 'pedido') {
    navigateTo(`/pedidos/${payload.pedidoId}`)
    return
  }

  const pagamento = pagamentos.value.find((item) => item.id === payload.id) ?? null
  if (!pagamento) return

  pagamentoDetalhes.value = pagamento
  detalhesAbertos.value = true
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Financeiro"
      subtitle="Acompanhe pagamentos, reembolsos e valores dos eventos."
    />

    <FinancialSummary :resumo="resumo" />

    <PaymentFilters
      :model-value="filtros"
      :eventos="eventoOptions"
      @update:model-value="atualizarFiltros"
    />

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">
        {{ total }}
        {{ total === 1 ? 'pagamento encontrado' : 'pagamentos encontrados' }}
      </p>

      <div class="w-full sm:w-48">
        <BaseSelect v-model="ordenacaoSelecionada" :options="sortOptions" />
      </div>
    </div>

    <PaymentEmptyState
      v-if="total === 0"
      :tem-filtros="temFiltros"
      @limpar="limparFiltros"
    />

    <template v-else>
      <div class="hidden lg:block">
        <PaymentTable :pagamentos="pagamentosPaginados" @action="acaoPagamento" />
      </div>

      <div class="lg:hidden">
        <PaymentMobileList :pagamentos="pagamentosPaginados" @action="acaoPagamento" />
      </div>

      <PaymentPagination
        v-if="numeroPaginas > 1"
        :pagina="pagina"
        :total-paginas="numeroPaginas"
        @ir="irPara"
      />
    </template>

    <PaymentDetailsModal
      :open="detalhesAbertos"
      :pagamento="pagamentoDetalhes"
      @close="detalhesAbertos = false"
    />
  </div>
</template>
