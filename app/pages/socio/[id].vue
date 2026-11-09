<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowLeftIcon,
  ArrowPathIcon,
  BanknotesIcon,
  CalendarDaysIcon,
  MapPinIcon,
  TicketIcon,
  UserGroupIcon,
  WalletIcon
} from '@heroicons/vue/24/outline'

import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import EntriesByHourChart from '~/components/EntriesByHourChart.vue'
import { obterVendasEventoSocio } from '~/services/socio'
import { formatDataHora, formatMoeda } from '~/utils/format'
import { percentualVendido, rotuloDia, type VendasEventoSocio } from '~/utils/socio'

definePageMeta({
  title: 'Vendas do evento',
  description: 'Números de venda do evento.',
  layout: 'admin-layout',
  sidebarActive: 'Vendas',
  middleware: ['socio-auth']
})

const route = useRoute()
const eventoId = String(route.params.id)

const dados = ref<VendasEventoSocio | null>(null)
const carregando = ref(true)
const erro = ref('')

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    dados.value = await obterVendasEventoSocio(eventoId)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar as vendas.'
  } finally {
    carregando.value = false
  }
}

onMounted(carregar)

const resumo = computed(() => dados.value?.evento.resumo ?? null)

const cards = computed(() => {
  const r = resumo.value
  if (!r) return []
  return [
    {
      icon: TicketIcon,
      label: 'Ingressos vendidos',
      value: `${r.vendidos}`,
      subtitle: r.capacidade ? `de ${r.capacidade} · ${percentualVendido(r)}% da capacidade` : `${r.pedidos} pedidos`
    },
    {
      icon: BanknotesIcon,
      label: 'Vendido (bruto)',
      value: formatMoeda(r.bruto),
      subtitle: `Ticket médio ${formatMoeda(r.ticketMedio)}`
    },
    {
      icon: WalletIcon,
      label: 'Líquido',
      value: formatMoeda(r.liquido),
      subtitle: 'Bruto menos taxa e reembolsos',
      valueClass: 'text-green-400'
    },
    {
      icon: UserGroupIcon,
      label: 'Já entraram',
      value: `${r.utilizados}`,
      subtitle: `${r.naoEntraram} ainda não entraram`,
      iconClass: 'text-green-500',
      circleClass: 'border-green-500/60'
    }
  ]
})

const detalhes = computed(() => {
  const r = resumo.value
  if (!r) return []
  return [
    { label: 'Taxa de serviço', value: formatMoeda(r.taxa), detail: 'Taxa da plataforma nas vendas online' },
    { label: 'Reembolsado', value: formatMoeda(r.reembolsado), detail: 'Devolvido aos compradores' },
    { label: 'Pedidos pagos', value: `${r.pedidos}`, detail: 'Compras confirmadas' },
    { label: 'Meia-entrada', value: `${r.meias}`, detail: 'Ingressos de meia vendidos' }
  ]
})

// So mostra o setor quando o evento tem mais de um (o padrao se chama "Ingresso").
const variosSetores = computed(() => new Set((dados.value?.porLote ?? []).map((l) => l.setor ?? '')).size > 1)

const maiorDia = computed(() => Math.max(1, ...(dados.value?.porDia ?? []).map((d) => d.ingressos)))
</script>

<template>
  <div class="space-y-6">
    <NuxtLink
      to="/socio"
      class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para meus eventos
    </NuxtLink>

    <div v-if="carregando && !dados" class="space-y-3" aria-busy="true">
      <div v-for="n in 3" :key="n" class="h-28 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />
    </div>

    <div
      v-else-if="erro && !dados"
      role="alert"
      class="rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center text-sm font-semibold text-red-300"
    >
      {{ erro }}
    </div>

    <template v-else-if="dados">
      <header class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <h1 class="text-2xl font-bold text-white">{{ dados.evento.nome }}</h1>
          <p class="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-zinc-400">
            <span class="flex items-center gap-1.5"><CalendarDaysIcon class="h-4 w-4" /> {{ formatDataHora(dados.evento.inicioEm) }}</span>
            <span v-if="dados.evento.local" class="flex items-center gap-1.5"><MapPinIcon class="h-4 w-4" /> {{ dados.evento.local }}</span>
            <span
              class="rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
              :class="dados.evento.vendasAbertas ? 'border-green-500/40 text-green-400' : 'border-zinc-700 text-zinc-400'"
            >
              Vendas {{ dados.evento.vendasAbertas ? 'abertas' : 'encerradas' }}
            </span>
          </p>
        </div>
        <button
          type="button"
          class="inline-flex w-fit items-center gap-2 rounded-xl border border-zinc-700 px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-zinc-300 transition-colors hover:border-zinc-600 hover:text-white disabled:opacity-50"
          :disabled="carregando"
          @click="carregar"
        >
          <ArrowPathIcon class="h-4 w-4" :class="carregando ? 'animate-spin' : ''" />
          Atualizar
        </button>
      </header>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 2xl:grid-cols-4">
        <DashboardMetricCard
          v-for="card in cards"
          :key="card.label"
          :icon="card.icon"
          :label="card.label"
          :value="card.value"
          :subtitle="card.subtitle"
          :value-class="card.valueClass"
          :icon-class="card.iconClass"
          :circle-class="card.circleClass"
        />
      </div>

      <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
        <div v-for="item in detalhes" :key="item.label" class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4">
          <p class="text-[11px] font-semibold uppercase tracking-[0.12em] text-zinc-500">{{ item.label }}</p>
          <p class="mt-1 text-lg font-semibold text-white">{{ item.value }}</p>
          <p class="mt-0.5 text-xs text-zinc-400">{{ item.detail }}</p>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <section class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4 sm:p-5">
          <h2 class="text-xs font-semibold uppercase tracking-[0.15em] text-zinc-500">Por forma de pagamento</h2>
          <p v-if="!dados.porForma.length" class="mt-3 text-sm text-zinc-500">Nenhuma venda ainda.</p>
          <ul v-else class="mt-3 divide-y divide-zinc-800">
            <li v-for="f in dados.porForma" :key="f.forma" class="flex items-center justify-between gap-3 py-2.5">
              <div>
                <p class="text-sm font-semibold text-white">{{ f.rotulo }}</p>
                <p class="text-xs text-zinc-500">{{ f.ingressos }} ingressos · {{ f.pedidos }} pedidos</p>
              </div>
              <p class="text-sm font-semibold text-zinc-200">{{ formatMoeda(f.valor) }}</p>
            </li>
          </ul>
        </section>

        <section class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4 sm:p-5">
          <h2 class="text-xs font-semibold uppercase tracking-[0.15em] text-zinc-500">Por lote</h2>
          <p v-if="!dados.porLote.length" class="mt-3 text-sm text-zinc-500">Nenhum lote cadastrado.</p>
          <ul v-else class="mt-3 divide-y divide-zinc-800">
            <li v-for="(l, i) in dados.porLote" :key="i" class="flex items-center justify-between gap-3 py-2.5">
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold text-white">
                  <template v-if="variosSetores && l.setor">{{ l.setor }} · </template>{{ l.lote }}
                </p>
                <p class="text-xs text-zinc-500">
                  {{ l.vendidos }} de {{ l.quantidade }} vendidos · {{ formatMoeda(l.preco) }}
                  <span v-if="l.status === 'ATIVO'" class="ml-1 text-amber-400">· atual</span>
                </p>
              </div>
              <p class="shrink-0 text-sm font-semibold text-zinc-200">{{ formatMoeda(l.valor) }}</p>
            </li>
          </ul>
        </section>
      </div>

      <section class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4 sm:p-5">
        <h2 class="text-xs font-semibold uppercase tracking-[0.15em] text-zinc-500">Vendas por dia</h2>
        <p v-if="!dados.porDia.length" class="mt-3 text-sm text-zinc-500">Nenhuma venda ainda.</p>
        <ul v-else class="mt-3 space-y-2">
          <li v-for="d in dados.porDia" :key="d.dia" class="grid grid-cols-[3.5rem_1fr_auto] items-center gap-3 text-sm">
            <span class="text-zinc-400">{{ rotuloDia(d.dia) }}</span>
            <div class="h-2.5 overflow-hidden rounded-full bg-zinc-800">
              <div class="h-full rounded-full bg-amber-400" :style="{ width: `${(d.ingressos / maiorDia) * 100}%` }" />
            </div>
            <span class="text-right text-zinc-200">{{ d.ingressos }} · {{ formatMoeda(d.valor) }}</span>
          </li>
        </ul>
      </section>

      <EntriesByHourChart v-if="dados.entradasPorHora.length" :data="dados.entradasPorHora" />
    </template>
  </div>
</template>
