<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  ArrowPathIcon,
  BanknotesIcon,
  BuildingStorefrontIcon,
  CalendarDaysIcon,
  CurrencyDollarIcon,
  ExclamationTriangleIcon,
  TicketIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import CartaoEventoPainel from '~/components/plataforma/CartaoEventoPainel.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { obterPainelPlataforma } from '~/services/admin/painelPlataforma'
import { formatHora, formatMoeda, formatNumero } from '~/utils/format'
import {
  OPCOES_PERIODO,
  inicioDoPeriodo,
  resumirNomes,
  variacao,
  type AtividadePainel,
  type EventoPainel,
  type PainelPlataforma,
  type PeriodoPainel
} from '~/utils/painelPlataforma'

definePageMeta({
  title: 'Painel da plataforma',
  description: 'Todas as casas do Ingressoudi em um só lugar.',
  layout: 'admin-layout',
  sidebarActive: 'Painel da plataforma',
  middleware: ['admin-auth']
})

const { operador, entrarNaCasa } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const periodo = ref<PeriodoPainel>('7_DIAS')
const painel = ref<PainelPlataforma | null>(null)
const carregando = ref(false)
const erro = ref('')
const abrindoId = ref('')

async function carregar() {
  if (!ehSuperAdmin.value) return
  carregando.value = true
  erro.value = ''
  try {
    painel.value = await obterPainelPlataforma(inicioDoPeriodo(periodo.value))
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o painel da plataforma.'
  } finally {
    carregando.value = false
  }
}

onMounted(() => void carregar())
watch(periodo, () => void carregar())

const m = computed(() => painel.value?.metricas)
const anterior = computed(() => painel.value?.anterior ?? null)

/** Abre a casa em modo suporte no destino escolhido. */
async function abrirCasa(organizacaoId: string, destino: string, chave = organizacaoId) {
  if (abrindoId.value) return
  abrindoId.value = chave
  erro.value = ''
  try {
    await entrarNaCasa(organizacaoId, destino)
  } catch {
    erro.value = 'Não foi possível entrar nessa casa.'
    abrindoId.value = ''
  }
}

function abrirEvento(e: EventoPainel) {
  void abrirCasa(e.organizacaoId, `/eventos/${e.id}/dashboard`, e.id)
}

interface Alerta {
  chave: string
  titulo: string
  detalhe: string
  grave: boolean
  botao: string
  acao: () => void
}

const alertas = computed<Alerta[]>(() => {
  const a = painel.value?.alertas
  if (!a) return []
  const itens: Alerta[] = []
  if (a.casasSemMercadoPago.length) {
    itens.push({
      chave: 'mp',
      titulo: `${a.casasSemMercadoPago.length} casa(s) aprovada(s) sem Mercado Pago conectado`,
      detalhe: `Não conseguem vender online · ${resumirNomes(a.casasSemMercadoPago.map((c) => c.nome))}`,
      grave: true,
      botao: 'Ver casas',
      acao: () => void navigateTo('/plataforma/organizacoes')
    })
  }
  if (a.pixRecusados.length) {
    const total = a.pixRecusados.reduce((soma, p) => soma + p.quantidade, 0)
    const principal = a.pixRecusados[0]!
    itens.push({
      chave: 'pix',
      titulo: `${total} Pix recusado(s) nas últimas 24h`,
      detalhe: `Mais em ${principal.nome} (${principal.quantidade})`,
      grave: true,
      botao: 'Ver pedidos',
      acao: () => void abrirCasa(principal.organizacaoId, '/pedidos', 'alerta-pix')
    })
  }
  if (a.casasSemEvento.length) {
    itens.push({
      chave: 'sem-evento',
      titulo: `${a.casasSemEvento.length} casa(s) há mais de 7 dias sem nenhum evento`,
      detalhe: `Bom momento para um contato · ${resumirNomes(a.casasSemEvento.map((c) => c.nome))}`,
      grave: false,
      botao: 'Ver no CRM',
      acao: () => void navigateTo('/plataforma/crm')
    })
  }
  if (a.eventosSemVendas.length) {
    itens.push({
      chave: 'sem-vendas',
      titulo: `${a.eventosSemVendas.length} evento(s) publicado(s) sem nenhuma venda`,
      detalhe: resumirNomes(a.eventosSemVendas.map((e) => `${e.nome} (${e.organizacaoNome})`), 2),
      grave: false,
      botao: 'Ver eventos',
      acao: () => void navigateTo('/plataforma/eventos')
    })
  }
  return itens
})

const maiorValorRanking = computed(() => Math.max(1, ...(painel.value?.ranking ?? []).map((r) => r.valor)))

function textoAtividade(a: AtividadePainel): { destaque: string; texto: string; tom: string } {
  switch (a.tipo) {
    case 'CASA_NOVA':
      return { destaque: 'Nova casa:', texto: `${a.organizacaoNome} se cadastrou`, tom: 'text-green-400' }
    case 'EVENTO_PUBLICADO':
      return { destaque: 'Evento publicado:', texto: `${a.eventoNome} · ${a.organizacaoNome}`, tom: 'text-amber-400' }
    case 'MERCADO_PAGO_CONECTADO':
      return { destaque: '', texto: `${a.organizacaoNome} conectou o Mercado Pago`, tom: '' }
    default:
      return {
        destaque: '',
        texto: `Venda de ${a.quantidade} ingresso(s) · ${a.eventoNome} · ${formatMoeda(a.valor)}`,
        tom: ''
      }
  }
}

function quando(iso: string): string {
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date())
  const dia = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date(iso))
  if (dia === hoje) return formatHora(iso)
  return new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit' }).format(new Date(iso))
}
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Painel da plataforma" subtitle="Todas as casas do Ingressoudi em um só lugar.">
      <template #actions>
        <div class="flex flex-wrap items-center gap-3">
          <SegmentedControl v-model="periodo" :options="OPCOES_PERIODO" :disabled="carregando" />
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
      </template>
    </PageHeader>

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

      <!-- Numeros do periodo -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5" :class="carregando ? 'opacity-60' : ''">
        <DashboardMetricCard
          :icon="BuildingStorefrontIcon"
          label="Casas ativas"
          :value="formatNumero(m?.casasAtivas ?? 0)"
          :subtitle="`+${formatNumero(m?.casasNovas ?? 0)} nova(s) · ${formatNumero(m?.casasEmAnalise ?? 0)} em análise`"
        />
        <DashboardMetricCard
          :icon="CalendarDaysIcon"
          label="Vendas abertas"
          :value="`${formatNumero(m?.eventosVendasAbertas ?? 0)} evento(s)`"
          :subtitle="`em ${formatNumero(m?.casasVendasAbertas ?? 0)} casa(s)`"
        />
        <DashboardMetricCard
          :icon="TicketIcon"
          label="Ingressos vendidos"
          :value="formatNumero(m?.ingressos ?? 0)"
          :subtitle="variacao(m?.ingressos ?? 0, anterior?.ingressos) || `${formatNumero(m?.pedidos ?? 0)} pedido(s) pago(s)`"
          subtitle-class="text-green-400"
        />
        <DashboardMetricCard
          :icon="BanknotesIcon"
          label="Vendido na plataforma"
          :value="formatMoeda(m?.valor ?? 0)"
          subtitle="Online + porta"
        />
        <DashboardMetricCard
          :icon="CurrencyDollarIcon"
          label="Sua receita (taxas)"
          :value="formatMoeda(m?.taxa ?? 0)"
          :subtitle="variacao(m?.taxa ?? 0, anterior?.taxa) || 'Vendas online'"
          value-class="text-amber-300"
          subtitle-class="text-green-400"
        />
      </div>

      <!-- Eventos acontecendo agora e nos proximos dias -->
      <section class="space-y-3">
        <div class="flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
            Acontecendo agora e nos próximos dias
          </h2>
          <NuxtLink to="/plataforma/eventos" class="text-xs font-medium text-amber-400 hover:text-amber-300">
            Todos os eventos →
          </NuxtLink>
        </div>
        <div v-if="carregando && !painel" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-busy="true">
          <div v-for="i in 4" :key="i" class="h-64 animate-pulse rounded-2xl bg-zinc-800/60" />
        </div>
        <BaseCard v-else-if="!painel?.eventos.length">
          <p class="text-sm text-zinc-500">Nenhum evento publicado para agora ou para os próximos 14 dias.</p>
        </BaseCard>
        <div v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <CartaoEventoPainel
            v-for="e in painel.eventos"
            :key="e.id"
            :evento="e"
            :abrindo="abrindoId !== ''"
            @abrir="abrirEvento"
          />
        </div>
        <p class="text-xs text-zinc-500">
          Clique num evento para abrir o dashboard dele em modo suporte, com as mesmas opções do produtor.
        </p>
      </section>

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-[1.45fr_1fr]">
        <!-- Ranking -->
        <BaseCard :padded="false" class="p-5 sm:p-6">
          <div class="mb-4 flex items-center justify-between gap-3">
            <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Ranking de casas no período</h3>
            <NuxtLink to="/plataforma/organizacoes" class="text-xs font-medium text-amber-400 hover:text-amber-300">
              Todas as organizações →
            </NuxtLink>
          </div>
          <p v-if="!painel?.ranking.length" class="text-sm text-zinc-500">Nenhuma venda no período.</p>
          <div v-else class="overflow-x-auto">
            <table class="w-full min-w-[560px] text-left text-sm">
              <thead>
                <tr class="text-xs uppercase tracking-wide text-zinc-500">
                  <th class="pb-3 pr-3 font-medium">#</th>
                  <th class="pb-3 pr-3 font-medium">Casa</th>
                  <th class="pb-3 pr-3 text-right font-medium">Ingressos</th>
                  <th class="pb-3 pr-3 text-right font-medium">Vendido</th>
                  <th class="pb-3 pr-3 text-right font-medium">Sua taxa</th>
                  <th class="w-32 pb-3 pr-3 font-medium">Participação</th>
                  <th class="pb-3" />
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-800">
                <tr v-for="(r, i) in painel.ranking" :key="r.organizacaoId">
                  <td class="py-3 pr-3 text-zinc-500">{{ i + 1 }}</td>
                  <td class="py-3 pr-3">
                    <NuxtLink
                      :to="`/plataforma/organizacoes/${r.organizacaoId}`"
                      class="whitespace-nowrap font-semibold text-white hover:text-amber-400"
                    >
                      {{ r.nome }}
                    </NuxtLink>
                  </td>
                  <td class="whitespace-nowrap py-3 pr-3 text-right text-zinc-300">{{ formatNumero(r.ingressos) }}</td>
                  <td class="whitespace-nowrap py-3 pr-3 text-right text-zinc-300">{{ formatMoeda(r.valor) }}</td>
                  <td class="whitespace-nowrap py-3 pr-3 text-right text-amber-300">{{ formatMoeda(r.taxa) }}</td>
                  <td class="py-3 pr-3">
                    <div class="h-1.5 overflow-hidden rounded-full bg-zinc-800">
                      <div
                        class="h-full rounded-full bg-amber-400"
                        :style="{ width: `${Math.round((r.valor / maiorValorRanking) * 100)}%` }"
                      />
                    </div>
                  </td>
                  <td class="py-3 text-right">
                    <AppButton
                      size="sm"
                      variant="ghost"
                      :disabled="abrindoId !== ''"
                      @click="abrirCasa(r.organizacaoId, '/painel')"
                    >
                      Acessar
                    </AppButton>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </BaseCard>

        <!-- Precisa de atencao -->
        <BaseCard :padded="false" class="p-5 sm:p-6">
          <h3 class="mb-2 text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Precisa de atenção</h3>
          <p v-if="!alertas.length" class="py-2 text-sm text-zinc-500">Nada pendente agora.</p>
          <ul v-else class="divide-y divide-zinc-800">
            <li v-for="a in alertas" :key="a.chave" class="flex items-start gap-3 py-3">
              <span
                class="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
                :class="a.grave ? 'bg-red-500/15 text-red-400' : 'bg-amber-400/15 text-amber-400'"
              >
                <ExclamationTriangleIcon class="h-4 w-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-white">{{ a.titulo }}</p>
                <p class="mt-0.5 text-xs text-zinc-500">{{ a.detalhe }}</p>
              </div>
              <AppButton size="sm" variant="outlineAccent" class="shrink-0" :disabled="abrindoId !== ''" @click="a.acao()">
                {{ a.botao }}
              </AppButton>
            </li>
          </ul>
        </BaseCard>
      </div>

      <!-- Atividade recente -->
      <BaseCard :padded="false" class="p-5 sm:p-6">
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Atividade recente</h3>
        <p v-if="!painel?.atividade.length" class="py-2 text-sm text-zinc-500">Nada nos últimos 7 dias.</p>
        <ul v-else class="divide-y divide-zinc-800">
          <li v-for="(a, i) in painel.atividade" :key="i" class="flex gap-3 py-2.5 text-sm">
            <span class="w-14 shrink-0 text-zinc-500">{{ quando(a.em) }}</span>
            <span class="min-w-0 text-zinc-300">
              <strong v-if="textoAtividade(a).destaque" :class="textoAtividade(a).tom">
                {{ textoAtividade(a).destaque }}
              </strong>
              {{ textoAtividade(a).texto }}
            </span>
          </li>
        </ul>
      </BaseCard>
    </template>
  </div>
</template>
