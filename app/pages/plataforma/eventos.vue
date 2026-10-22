<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowPathIcon,
  ArrowTopRightOnSquareIcon,
  BanknotesIcon,
  BuildingStorefrontIcon,
  CalendarDaysIcon,
  CurrencyDollarIcon,
  MagnifyingGlassIcon,
  PresentationChartBarIcon,
  TicketIcon
} from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import EventPublicationBadge from '~/components/eventos/EventPublicationBadge.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { listarEventosPlataforma } from '~/services/admin/eventosPlataforma'
import {
  casasDosEventos,
  filtrarEventosPlataforma,
  resumirEventosPlataforma,
  type EventoPlataforma,
  type SituacaoEvento
} from '~/utils/eventosPlataforma'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import { rotaEvento } from '~/utils/rotasPublicas'

definePageMeta({
  title: 'Todos os eventos',
  description: 'Eventos de todas as casas da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Todos os eventos',
  middleware: ['operator-auth']
})

const { operador, entrarNaCasa } = useOperatorAuth()
const abrindoId = ref('')

/** Abre o dashboard do evento em modo suporte (entra na casa dele). */
async function abrirDashboard(e: EventoPlataforma) {
  if (abrindoId.value) return
  abrindoId.value = e.id
  erro.value = ''
  try {
    await entrarNaCasa(e.organizacaoId, `/eventos/${e.id}/dashboard`)
  } catch {
    erro.value = 'Não foi possível entrar na casa deste evento.'
    abrindoId.value = ''
  }
}
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const eventos = ref<EventoPlataforma[]>([])
const carregando = ref(false)
const erro = ref('')

const busca = ref('')
const organizacaoId = ref('')
const situacao = ref<SituacaoEvento>('PROXIMOS')

const opcoesSituacao = [
  { value: 'PROXIMOS', label: 'Próximos' },
  { value: 'PASSADOS', label: 'Encerrados' },
  { value: 'TODOS', label: 'Todos' }
]

const opcoesCasas = computed(() => [
  { value: '', label: 'Todas as casas' },
  ...casasDosEventos(eventos.value).map((c) => ({ value: c.id, label: c.nome }))
])

const lista = computed(() =>
  filtrarEventosPlataforma(eventos.value, {
    busca: busca.value,
    organizacaoId: organizacaoId.value,
    situacao: situacao.value
  })
)
const resumo = computed(() => resumirEventosPlataforma(lista.value))

function linkPublico(e: EventoPlataforma): string {
  return rotaEvento(e.organizacaoSlug, e.slug)
}

async function carregar() {
  if (!ehSuperAdmin.value) return
  carregando.value = true
  erro.value = ''
  try {
    eventos.value = await listarEventosPlataforma()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os eventos.'
  } finally {
    carregando.value = false
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Todos os eventos" subtitle="Eventos criados por todas as casas da plataforma." />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <!-- Filtros -->
      <BaseCard class="space-y-4">
        <div class="grid grid-cols-1 gap-3 md:grid-cols-[1fr_16rem]">
          <div class="relative">
            <BaseInput v-model="busca" placeholder="Buscar por evento, casa ou local" />
            <MagnifyingGlassIcon class="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500" />
          </div>
          <BaseSelect v-model="organizacaoId" :options="opcoesCasas" />
        </div>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <SegmentedControl v-model="situacao" :options="opcoesSituacao" :disabled="carregando" />
          <button
            type="button"
            class="inline-flex items-center gap-1.5 text-xs uppercase tracking-wide text-zinc-500 hover:text-zinc-300"
            :disabled="carregando"
            @click="carregar"
          >
            <ArrowPathIcon class="h-4 w-4" :class="carregando ? 'animate-spin' : ''" />
            Atualizar
          </button>
        </div>
      </BaseCard>

      <p
        v-if="erro"
        role="alert"
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        {{ erro }}
      </p>

      <!-- Resumo da lista filtrada -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4" :class="carregando ? 'opacity-60' : ''">
        <DashboardMetricCard
          :icon="CalendarDaysIcon"
          label="Eventos"
          :value="formatNumero(resumo.eventos)"
          :subtitle="`${formatNumero(resumo.casas)} casa(s)`"
        />
        <DashboardMetricCard
          :icon="TicketIcon"
          label="Ingressos vendidos"
          :value="formatNumero(resumo.ingressosVendidos)"
          subtitle="Válidos e já utilizados"
        />
        <DashboardMetricCard
          :icon="BanknotesIcon"
          label="Valor vendido"
          :value="formatMoeda(resumo.valorVendido)"
          subtitle="Pedidos pagos, online e na porta"
        />
        <DashboardMetricCard
          :icon="CurrencyDollarIcon"
          label="Sua receita (taxas)"
          :value="formatMoeda(resumo.taxaPlataforma)"
          subtitle="Nesses eventos"
          value-class="text-amber-300"
        />
      </div>

      <!-- Lista -->
      <BaseCard :padded="false" class="overflow-hidden">
        <div v-if="carregando && eventos.length === 0" class="space-y-3 p-5" aria-busy="true">
          <div v-for="i in 3" :key="i" class="h-16 animate-pulse rounded-xl bg-zinc-800/60" />
        </div>

        <p v-else-if="lista.length === 0" class="p-5 text-sm text-zinc-500">
          Nenhum evento encontrado com esses filtros.
        </p>

        <ul v-else class="divide-y divide-zinc-800">
          <li
            v-for="e in lista"
            :key="e.id"
            class="flex flex-col gap-4 p-5 lg:flex-row lg:items-center"
          >
            <div class="flex min-w-0 flex-1 gap-4">
              <div class="h-16 w-24 shrink-0 overflow-hidden rounded-lg border border-zinc-800 bg-zinc-950">
                <img v-if="e.imagemUrl" :src="e.imagemUrl" :alt="e.nome" class="h-full w-full object-cover" />
                <div v-else class="flex h-full w-full items-center justify-center">
                  <CalendarDaysIcon class="h-6 w-6 text-zinc-700" />
                </div>
              </div>
              <div class="min-w-0">
                <p class="truncate font-semibold text-white">{{ e.nome }}</p>
                <p class="mt-0.5 flex items-center gap-1.5 truncate text-xs text-amber-300/90">
                  <BuildingStorefrontIcon class="h-3.5 w-3.5 shrink-0" />
                  {{ e.organizacaoNome }}
                </p>
                <p class="mt-0.5 truncate text-xs text-zinc-500">
                  {{ formatDataHora(e.inicioEm) }} · {{ e.local }}
                </p>
                <div class="mt-2 flex flex-wrap items-center gap-1.5">
                  <EventStatusBadge :status="e.status" />
                  <EventPublicationBadge :status="e.publicacaoStatus" />
                  <span
                    class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
                    :class="e.vendasStatus === 'ABERTAS' ? 'border-green-500/30 text-green-300' : 'border-zinc-700 text-zinc-500'"
                  >
                    {{ e.vendasStatus === 'ABERTAS' ? 'Vendas abertas' : 'Vendas encerradas' }}
                  </span>
                  <span
                    v-if="e.meiaEntradaAtiva"
                    class="inline-flex items-center rounded-full border border-amber-400/30 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
                  >
                    Meia-entrada
                  </span>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-3 gap-4 text-xs lg:w-[26rem] lg:shrink-0">
              <div>
                <p class="text-zinc-500">Vendidos</p>
                <p class="text-sm font-semibold text-white">{{ formatNumero(e.vendidos) }}</p>
                <p class="text-zinc-600">{{ formatNumero(e.disponiveis) }} disponíveis</p>
              </div>
              <div>
                <p class="text-zinc-500">Vendido</p>
                <p class="text-sm font-semibold text-white">{{ formatMoeda(e.valorVendido) }}</p>
                <p class="text-zinc-600">{{ formatNumero(e.pedidosPagos) }} pedido(s)</p>
              </div>
              <div>
                <p class="text-zinc-500">Sua taxa</p>
                <p class="text-sm font-semibold text-amber-300">{{ formatMoeda(e.taxaPlataforma) }}</p>
                <p class="truncate text-zinc-600">
                  {{ e.loteAtual ? `${e.loteAtual.nome} · ${formatMoeda(e.loteAtual.preco)}` : 'Sem lote ativo' }}
                </p>
              </div>
            </div>

            <div class="flex shrink-0 flex-wrap gap-2">
            <button
              type="button"
              class="inline-flex shrink-0 items-center justify-center gap-1.5 rounded-lg border border-amber-400/60 px-3 py-2 text-xs font-medium text-amber-400 transition-colors hover:bg-amber-400/10 disabled:opacity-50"
              :disabled="abrindoId !== ''"
              @click="abrirDashboard(e)"
            >
              <PresentationChartBarIcon class="h-4 w-4" />
              {{ abrindoId === e.id ? 'Abrindo...' : 'Abrir dashboard' }}
            </button>
            <a
              :href="linkPublico(e)"
              target="_blank"
              rel="noopener"
              class="inline-flex shrink-0 items-center justify-center gap-1.5 rounded-lg border border-zinc-700 px-3 py-2 text-xs font-medium text-zinc-300 transition-colors hover:border-amber-400/60 hover:text-amber-400"
            >
              <ArrowTopRightOnSquareIcon class="h-4 w-4" />
              Ver página
            </a>
            </div>
          </li>
        </ul>
      </BaseCard>

      <p class="text-xs leading-relaxed text-zinc-500">
        "Abrir dashboard" entra na casa do evento em modo suporte, com as mesmas opções do produtor.
        Eventos em rascunho não abrem para o público.
      </p>
    </template>
  </div>
</template>
