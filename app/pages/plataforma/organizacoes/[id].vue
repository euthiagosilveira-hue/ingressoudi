<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import {
  ArrowLeftIcon,
  ArrowPathIcon,
  ArrowTopRightOnSquareIcon,
  BanknotesIcon,
  CalendarDaysIcon,
  ClipboardDocumentIcon,
  CurrencyDollarIcon,
  ReceiptRefundIcon,
  TicketIcon,
  UserCircleIcon
} from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import EventPublicationBadge from '~/components/eventos/EventPublicationBadge.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { obterOrganizacaoPlataforma } from '~/services/admin/organizacoes'
import { formatDataHora, formatDataHoraCompleta, formatDataNumerica, formatMoeda, formatNumero } from '~/utils/format'
import {
  filtrarEventosCasa,
  percentual,
  repasseOnline,
  ticketMedio,
  type DetalheCasa,
  type FiltroEventosCasa
} from '~/utils/organizacaoPlataforma'
import { rotaEvento, rotaOrganizacao } from '~/utils/rotasPublicas'
import { useRoute } from '#imports'

definePageMeta({
  title: 'Detalhes da casa',
  description: 'Dono, equipe e números de uma casa da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Organizações',
  middleware: ['operator-auth']
})

const route = useRoute()
const { operador } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))
const organizacaoId = computed(() => String(route.params.id ?? ''))

const casa = ref<DetalheCasa | null>(null)
const carregando = ref(false)
const erro = ref('')
const filtro = ref<FiltroEventosCasa>('TODOS')

const opcoesFiltro = [
  { value: 'TODOS', label: 'Todos' },
  { value: 'ATIVOS', label: 'Ativos' },
  { value: 'REALIZADOS', label: 'Realizados' },
  { value: 'RASCUNHOS', label: 'Rascunhos' }
]

const m = computed(() => casa.value?.metricas)
const eventos = computed(() => (casa.value ? filtrarEventosCasa(casa.value.eventos, filtro.value) : []))
const comparecimento = computed(() => (m.value ? percentual(m.value.ingressosUtilizados, m.value.ingressosVendidos) : null))

async function carregar() {
  if (!ehSuperAdmin.value || !organizacaoId.value) return
  carregando.value = true
  erro.value = ''
  try {
    casa.value = await obterOrganizacaoPlataforma(organizacaoId.value)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar a casa.'
  } finally {
    carregando.value = false
  }
}

async function copiar(texto: string) {
  try {
    await navigator.clipboard.writeText(texto)
    toast.success('E-mail copiado.')
  } catch {
    toast.error('Não foi possível copiar.')
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <NuxtLink
      to="/plataforma/organizacoes"
      class="inline-flex items-center gap-1.5 text-xs uppercase tracking-wide text-zinc-500 hover:text-zinc-300"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Organizações
    </NuxtLink>

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <p
        v-if="erro"
        role="alert"
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        {{ erro }}
      </p>

      <div v-if="carregando && !casa" class="space-y-3" aria-busy="true">
        <div v-for="i in 3" :key="i" class="h-24 animate-pulse rounded-xl bg-zinc-800/60" />
      </div>

      <template v-if="casa && m">
        <PageHeader :title="casa.organizacao.nome" :subtitle="`Casa criada em ${formatDataNumerica(casa.organizacao.criadoEm)}`">
          <template #actions>
            <a
              :href="rotaOrganizacao(casa.organizacao.slug)"
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-700 px-3 py-2 text-xs font-medium text-zinc-300 hover:border-amber-400/60 hover:text-amber-400"
            >
              <ArrowTopRightOnSquareIcon class="h-4 w-4" />
              /{{ casa.organizacao.slug }}
            </a>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 text-xs uppercase tracking-wide text-zinc-500 hover:text-zinc-300"
              :disabled="carregando"
              @click="carregar"
            >
              <ArrowPathIcon class="h-4 w-4" :class="carregando ? 'animate-spin' : ''" />
              Atualizar
            </button>
          </template>
        </PageHeader>

        <div class="flex flex-wrap items-center gap-1.5">
          <span
            class="rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
            :class="casa.organizacao.aprovada ? 'border-emerald-400/30 text-emerald-300' : 'border-amber-400/30 text-amber-300'"
          >
            {{ casa.organizacao.aprovada ? 'Aprovada' : 'Em análise' }}
          </span>
          <span
            v-if="!casa.organizacao.ativo"
            class="rounded-full border border-zinc-600 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-400"
          >
            Inativa
          </span>
          <span
            class="rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
            :class="casa.organizacao.mercadoPago ? 'border-sky-400/30 text-sky-300' : 'border-red-500/30 text-red-300'"
          >
            {{ casa.organizacao.mercadoPago ? 'Mercado Pago conectado' : 'Sem Mercado Pago' }}
          </span>
          <span
            v-if="casa.organizacao.listaVip"
            class="rounded-full border border-sky-400/30 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-sky-300"
          >
            Lista VIP
          </span>
        </div>

        <!-- Metricas -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <DashboardMetricCard
            :icon="BanknotesIcon"
            label="Faturamento total"
            :value="formatMoeda(m.valorVendido)"
            :subtitle="`${formatMoeda(m.valorOnline)} online · ${formatMoeda(m.valorDinheiro)} em dinheiro`"
          />
          <DashboardMetricCard
            :icon="CurrencyDollarIcon"
            label="Sua receita (taxas)"
            :value="formatMoeda(m.taxaPlataforma)"
            :subtitle="`Repasse online ao produtor: ${formatMoeda(repasseOnline(m))}`"
            value-class="text-amber-300"
          />
          <DashboardMetricCard
            :icon="CalendarDaysIcon"
            label="Eventos publicados"
            :value="formatNumero(m.eventosPublicados)"
            :subtitle="`${formatNumero(m.eventosAtivos)} ativo(s) agora · ${formatNumero(m.eventosRealizados)} realizado(s) · ${formatNumero(m.eventosRascunho)} rascunho(s)`"
          />
          <DashboardMetricCard
            :icon="TicketIcon"
            label="Ingressos vendidos"
            :value="formatNumero(m.ingressosVendidos)"
            :subtitle="comparecimento === null ? 'Nenhuma entrada ainda' : `${formatNumero(m.ingressosUtilizados)} entraram (${comparecimento}%)`"
          />
          <DashboardMetricCard
            :icon="TicketIcon"
            label="Ticket médio"
            :value="formatMoeda(ticketMedio(m.valorVendido, m.ingressosVendidos))"
            :subtitle="`${formatNumero(m.pedidosPagos)} pedido(s) pago(s)`"
          />
          <DashboardMetricCard
            :icon="ReceiptRefundIcon"
            label="Reembolsado"
            :value="formatMoeda(m.valorReembolsado)"
            :subtitle="m.proximoEventoEm ? `Próximo evento: ${formatDataHora(m.proximoEventoEm)}` : 'Nenhum evento futuro publicado'"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <!-- Dono -->
          <BaseCard>
            <h2 class="text-sm font-semibold text-white">Dono da casa</h2>
            <template v-if="casa.dono">
              <p class="mt-3 flex items-center gap-1.5 text-sm font-medium text-zinc-100">
                <UserCircleIcon class="h-5 w-5 text-zinc-500" />
                {{ casa.dono.nome }}
                <span v-if="!casa.dono.ativo" class="text-xs font-normal text-red-300">(conta desativada)</span>
              </p>
              <div class="mt-1 flex items-center gap-2">
                <a :href="`mailto:${casa.dono.email}`" class="truncate text-sm text-amber-300 hover:underline">{{ casa.dono.email }}</a>
                <button
                  type="button"
                  class="rounded p-1 text-zinc-500 hover:bg-zinc-800 hover:text-zinc-200"
                  aria-label="Copiar e-mail do dono"
                  @click="copiar(casa.dono.email)"
                >
                  <ClipboardDocumentIcon class="h-4 w-4" />
                </button>
              </div>
              <dl class="mt-3 space-y-1.5 text-xs">
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Conta criada</dt>
                  <dd class="text-zinc-300">{{ casa.dono.cadastradoEm ? formatDataHoraCompleta(casa.dono.cadastradoEm) : '—' }}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Último acesso</dt>
                  <dd class="text-zinc-300">{{ casa.dono.ultimoAcessoEm ? formatDataHoraCompleta(casa.dono.ultimoAcessoEm) : 'nunca' }}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">E-mail confirmado</dt>
                  <dd :class="casa.dono.emailConfirmado ? 'text-zinc-300' : 'text-amber-300'">{{ casa.dono.emailConfirmado ? 'Sim' : 'Não' }}</dd>
                </div>
                <div class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Termos de uso</dt>
                  <dd class="text-zinc-300">
                    {{ casa.dono.termosAceitosEm
                      ? `Versão ${casa.dono.termosVersao ?? '?'} em ${formatDataNumerica(casa.dono.termosAceitosEm)}`
                      : 'Não registrado' }}
                  </dd>
                </div>
                <div v-if="casa.dono.outrasCasas > 0" class="flex justify-between gap-3">
                  <dt class="text-zinc-500">Outras casas</dt>
                  <dd class="text-zinc-300">{{ formatNumero(casa.dono.outrasCasas) }}</dd>
                </div>
              </dl>
            </template>
            <p v-else class="mt-3 text-sm text-zinc-500">Nenhum administrador ativo nesta casa.</p>
          </BaseCard>

          <!-- Configuracao -->
          <BaseCard>
            <h2 class="text-sm font-semibold text-white">Configuração</h2>
            <dl class="mt-3 space-y-1.5 text-xs">
              <div class="flex justify-between gap-3">
                <dt class="text-zinc-500">Taxa de serviço</dt>
                <dd class="text-zinc-300">{{ formatMoeda(casa.organizacao.taxaServico) }} por ingresso online</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-zinc-500">Mercado Pago</dt>
                <dd class="text-zinc-300">
                  {{ casa.organizacao.mercadoPago
                    ? `Conectado${casa.organizacao.mercadoPago.conectadoEm ? ` em ${formatDataNumerica(casa.organizacao.mercadoPago.conectadoEm)}` : ''}${casa.organizacao.mercadoPago.producao ? '' : ' (modo teste)'}`
                    : 'Não conectado' }}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-zinc-500">Lista VIP</dt>
                <dd class="text-zinc-300">{{ casa.organizacao.listaVip ? 'Liberada' : 'Desligada' }}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-zinc-500">Eventos cancelados</dt>
                <dd class="text-zinc-300">{{ formatNumero(m.eventosCancelados) }}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-zinc-500">Com vendas abertas agora</dt>
                <dd class="text-zinc-300">{{ formatNumero(m.eventosVendasAbertas) }}</dd>
              </div>
            </dl>
            <p class="mt-3 text-xs text-zinc-600">Taxa, Lista VIP e aprovação se alteram na lista de Organizações.</p>
          </BaseCard>
        </div>

        <!-- Equipe -->
        <BaseCard :padded="false" class="overflow-hidden">
          <h2 class="px-5 pt-5 text-sm font-semibold text-white">Equipe ({{ casa.equipe.length }})</h2>
          <ul class="mt-3 divide-y divide-zinc-800">
            <li
              v-for="u in casa.equipe"
              :key="u.usuarioId"
              class="flex flex-col gap-1 px-5 py-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0">
                <p class="flex items-center gap-2 truncate text-sm text-zinc-100">
                  {{ u.nome }}
                  <span v-if="u.dono" class="rounded-full border border-amber-400/30 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300">Dono</span>
                  <span v-if="!u.ativo" class="rounded-full border border-zinc-600 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-400">Inativo</span>
                </p>
                <p class="truncate text-xs text-zinc-500">{{ u.email }}</p>
              </div>
              <p class="shrink-0 text-xs text-zinc-500">
                {{ u.perfil === 'PORTARIA' ? 'Portaria' : 'Administrador' }} · último acesso
                {{ u.ultimoAcessoEm ? formatDataNumerica(u.ultimoAcessoEm) : 'nunca' }}
              </p>
            </li>
          </ul>
        </BaseCard>

        <!-- Eventos -->
        <BaseCard :padded="false" class="overflow-hidden">
          <div class="flex flex-wrap items-center justify-between gap-3 px-5 pt-5">
            <h2 class="text-sm font-semibold text-white">Eventos ({{ casa.eventos.length }})</h2>
            <SegmentedControl v-model="filtro" :options="opcoesFiltro" />
          </div>
          <p v-if="eventos.length === 0" class="p-5 text-sm text-zinc-500">Nenhum evento neste filtro.</p>
          <ul v-else class="mt-3 divide-y divide-zinc-800">
            <li v-for="e in eventos" :key="e.id" class="flex flex-col gap-3 px-5 py-4 lg:flex-row lg:items-center">
              <div class="min-w-0 flex-1">
                <a
                  :href="rotaEvento(casa.organizacao.slug, e.slug)"
                  target="_blank"
                  rel="noopener"
                  class="truncate font-semibold text-white hover:text-amber-400"
                >
                  {{ e.nome }}
                </a>
                <p class="mt-0.5 truncate text-xs text-zinc-500">{{ formatDataHora(e.inicioEm) }} · {{ e.local }}</p>
                <div class="mt-2 flex flex-wrap items-center gap-1.5">
                  <EventStatusBadge :status="e.status" />
                  <EventPublicationBadge :status="e.publicacaoStatus" />
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4 text-xs sm:grid-cols-4 lg:w-[34rem] lg:shrink-0">
                <div>
                  <p class="text-zinc-500">Vendidos</p>
                  <p class="text-sm font-semibold text-white">{{ formatNumero(e.vendidos) }}</p>
                  <p class="text-zinc-600">de {{ formatNumero(e.capacidadeTotal) }}</p>
                </div>
                <div>
                  <p class="text-zinc-500">Entradas</p>
                  <p class="text-sm font-semibold text-white">{{ formatNumero(e.utilizados) }}</p>
                  <p class="text-zinc-600">
                    {{ percentual(e.utilizados, e.vendidos) === null ? '—' : `${percentual(e.utilizados, e.vendidos)}%` }}
                  </p>
                </div>
                <div>
                  <p class="text-zinc-500">Faturamento</p>
                  <p class="text-sm font-semibold text-white">{{ formatMoeda(e.valorVendido) }}</p>
                  <p class="text-zinc-600">{{ formatMoeda(e.valorDinheiro) }} em dinheiro</p>
                </div>
                <div>
                  <p class="text-zinc-500">Sua taxa</p>
                  <p class="text-sm font-semibold text-amber-300">{{ formatMoeda(e.taxaPlataforma) }}</p>
                  <p class="text-zinc-600">{{ formatNumero(e.pedidosPagos) }} pedido(s)</p>
                </div>
              </div>
            </li>
          </ul>
        </BaseCard>

        <p class="text-xs leading-relaxed text-zinc-500">
          Faturamento considera pedidos pagos, online e em dinheiro. Dono é quem cadastrou a casa; sem esse registro,
          aparece o administrador mais antigo. Dados pessoais: use só para suporte e contato com a casa.
        </p>
      </template>
    </template>
  </div>
</template>
