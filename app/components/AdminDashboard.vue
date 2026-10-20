<script setup lang="ts">
import { computed } from 'vue'
import type { Component } from 'vue'
import {
  BanknotesIcon,
  ClockIcon,
  CreditCardIcon,
  TicketIcon,
  UserGroupIcon
} from '@heroicons/vue/24/outline'

import { useAdminDashboard } from '~/composables/useAdminDashboard'
import { formatMoeda } from '~/utils/format'

interface Metric {
  icon: Component
  label: string
  value: string
  subtitle: string
  iconClass?: string
  circleClass?: string
  valueClass?: string
  subtitleClass?: string
}

const props = defineProps<{
  /** Quando informado, o dashboard mostra so este evento. */
  eventoId?: string
}>()

const { viewModel, extras, erro } = useAdminDashboard(props.eventoId)

const resumoEvento = computed(() => {
  const x = extras.value
  if (!x) return []
  return [
    {
      label: 'Lote atual',
      value: x.loteAtual ? `${x.loteAtual.nome} · ${formatMoeda(Number(x.loteAtual.preco))}` : 'Nenhum lote ativo',
      detail: x.loteAtual ? `${x.loteAtual.disponiveis} ingressos disponíveis` : 'Ative um lote em Lotes'
    },
    {
      label: 'Vendas',
      value: x.vendasStatus === 'ABERTAS' ? 'Abertas' : 'Encerradas',
      detail: `Capacidade de ${x.capacidadeTotal} pessoas`
    },
    {
      label: 'Reservas em aberto',
      value: `${x.reservasAtivas}`,
      detail: 'Pedidos aguardando pagamento'
    },
    {
      label: 'Reembolsado',
      value: formatMoeda(Number(x.valorReembolsado)),
      detail: 'Devolvido aos compradores'
    }
  ]
})

function percentual(valor: number, total: number): string {
  if (total <= 0) return '0% do total'
  return `${((valor / total) * 100).toFixed(2).replace('.', ',')}% do total`
}

const metrics = computed<Metric[]>(() => {
  const m = viewModel.value.metrics
  return [
    {
      icon: TicketIcon,
      label: 'Vendidos',
      value: `${m.vendidos} ingressos`,
      subtitle: formatMoeda(m.faturamento),
      iconClass: 'text-amber-400',
      circleClass: 'border-amber-400/60'
    },
    {
      icon: UserGroupIcon,
      label: 'Utilizados',
      value: `${m.utilizados} ingressos`,
      subtitle: percentual(m.utilizados, m.vendidos),
      iconClass: 'text-green-500',
      circleClass: 'border-green-500/60',
      subtitleClass: 'text-green-400'
    },
    {
      icon: ClockIcon,
      label: 'Ainda não entraram',
      value: `${m.naoEntraram} ingressos`,
      subtitle: percentual(m.naoEntraram, m.vendidos),
      iconClass: 'text-amber-400',
      circleClass: 'border-amber-400/60'
    },
    {
      icon: BanknotesIcon,
      label: 'Faturamento',
      value: formatMoeda(m.faturamento),
      subtitle: 'Confirmado',
      iconClass: 'text-amber-400',
      circleClass: 'border-amber-400/60',
      subtitleClass: 'text-green-400'
    },
    {
      icon: CreditCardIcon,
      label: 'Ticket médio',
      value: formatMoeda(m.ticketMedio),
      subtitle: 'por ingresso',
      iconClass: 'text-amber-400',
      circleClass: 'border-amber-400/60'
    }
  ]
})
</script>

<template>
  <div
    v-if="erro && props.eventoId"
    role="alert"
    class="rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center text-sm font-semibold text-red-300"
  >
    {{ erro }}
  </div>

  <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
    <DashboardMetricCard
      v-for="metric in metrics"
      :key="metric.label"
      :icon="metric.icon"
      :label="metric.label"
      :value="metric.value"
      :subtitle="metric.subtitle"
      :icon-class="metric.iconClass"
      :circle-class="metric.circleClass"
      :value-class="metric.valueClass"
      :subtitle-class="metric.subtitleClass"
    />
  </div>

  <div v-if="resumoEvento.length" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
    <div
      v-for="item in resumoEvento"
      :key="item.label"
      class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4"
    >
      <p class="text-xs font-semibold uppercase tracking-[0.15em] text-zinc-500">{{ item.label }}</p>
      <p class="mt-1 text-lg font-semibold text-white">{{ item.value }}</p>
      <p class="mt-0.5 text-xs text-zinc-400">{{ item.detail }}</p>
    </div>
  </div>

  <div class="grid grid-cols-1 gap-4 lg:grid-cols-2 xl:grid-cols-12">
    <TodayEventCard class="lg:col-span-1 xl:col-span-4" :event="viewModel.evento" />
    <EntriesByHourChart class="lg:col-span-1 xl:col-span-5" :data="viewModel.entriesByHour" />
    <PaymentStatusChart class="lg:col-span-2 xl:col-span-3" :data="viewModel.paymentStatus" />
  </div>

  <div class="grid grid-cols-1 gap-4 xl:grid-cols-12">
    <RecentOrders class="xl:col-span-8" :orders="viewModel.recentOrders" />
    <RecentEntries class="xl:col-span-4" :entries="viewModel.recentEntries" />
  </div>
</template>
