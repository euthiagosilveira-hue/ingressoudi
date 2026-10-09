<script setup lang="ts">
import { computed } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import OrderEmptyState from '~/components/pedidos/OrderEmptyState.vue'
import OrderFilters from '~/components/pedidos/OrderFilters.vue'
import OrderMobileList from '~/components/pedidos/OrderMobileList.vue'
import OrderPagination from '~/components/pedidos/OrderPagination.vue'
import OrderSummary from '~/components/pedidos/OrderSummary.vue'
import OrderTable from '~/components/pedidos/OrderTable.vue'
import PageHeader from '~/components/PageHeader.vue'
import { useAdminOrders } from '~/composables/useAdminOrders'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import type { SelectOption } from '~/types/ui'
import type { OrderFiltersState, OrderSort } from '~/types/pedido'

const { operador } = useOperatorAuth()
const isAdmin = computed(() => operador.value?.perfil === 'ADMINISTRADOR')

const {
  filtros,
  ordenacao,
  pagina,
  pedidosPaginados,
  total,
  numeroPaginas,
  resumo,
  temFiltros,
  limparFiltros,
  irPara,
  eventoOptions
} = useAdminOrders(10)

const sortOptions: SelectOption[] = [
  { value: 'RECENTES', label: 'Mais recentes' },
  { value: 'ANTIGOS', label: 'Mais antigos' }
]

const ordenacaoSelecionada = computed({
  get: () => ordenacao.value,
  set: (valor: string) => {
    ordenacao.value = valor as OrderSort
  }
})

function atualizarFiltros(valor: OrderFiltersState) {
  Object.assign(filtros, valor)
}

function acaoPedido(payload: { id: string; action: string }) {
  if (payload.action === 'ingressos') {
    navigateTo(`/pedidos/${payload.id}#order-tickets`)
    return
  }

  if (payload.action === 'pagamento') {
    navigateTo(`/pedidos/${payload.id}#order-payment`)
    return
  }

  navigateTo(`/pedidos/${payload.id}`)
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Pedidos" subtitle="Acompanhe reservas, pagamentos e vendas dos eventos.">
      <template #actions>
        <AppButton v-if="isAdmin" variant="primary" to="/pedidos/nova-venda">
          Nova venda manual
        </AppButton>
      </template>
    </PageHeader>

    <OrderSummary :resumo="resumo" />

    <OrderFilters :model-value="filtros" :eventos="eventoOptions" @update:model-value="atualizarFiltros" />

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm text-zinc-500">
        {{ total }}
        {{ total === 1 ? 'pedido encontrado' : 'pedidos encontrados' }}
      </p>

      <div class="w-full sm:w-44">
        <BaseSelect v-model="ordenacaoSelecionada" :options="sortOptions" />
      </div>
    </div>

    <OrderEmptyState
      v-if="total === 0"
      :tem-filtros="temFiltros"
      @limpar="limparFiltros"
    />

    <template v-else>
      <div class="hidden lg:block">
        <OrderTable :pedidos="pedidosPaginados" @action="acaoPedido" />
      </div>

      <div class="lg:hidden">
        <OrderMobileList :pedidos="pedidosPaginados" @action="acaoPedido" />
      </div>

      <OrderPagination
        v-if="numeroPaginas > 1"
        :pagina="pagina"
        :total-paginas="numeroPaginas"
        @ir="irPara"
      />
    </template>
  </div>
</template>
