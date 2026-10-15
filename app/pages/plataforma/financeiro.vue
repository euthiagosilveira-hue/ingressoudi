<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  ArrowPathIcon,
  BanknotesIcon,
  BuildingStorefrontIcon,
  CurrencyDollarIcon,
  TicketIcon
} from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import DashboardMetricCard from '~/components/DashboardMetricCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { obterFinanceiroPlataforma, type FinanceiroPlataforma } from '~/services/admin/financeiroPlataforma'
import { formatMoeda, formatNumero } from '~/utils/format'
import {
  PRESETS_PERIODO,
  formatarDiaIso,
  periodoDoPreset,
  validarPeriodo,
  type Periodo,
  type PresetPeriodo
} from '~/utils/financeiroPlataforma'

definePageMeta({
  title: 'Receita da plataforma',
  description: 'Vendas e taxas de todas as casas da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Receita da plataforma',
  middleware: ['operator-auth']
})

const { operador } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const preset = ref<PresetPeriodo>('30D')
const periodo = ref<Periodo>(periodoDoPreset('30D') as Periodo)
const dados = ref<FinanceiroPlataforma | null>(null)
const carregando = ref(false)
const erro = ref('')

const opcoes = PRESETS_PERIODO.map((p) => ({ value: p.value, label: p.label }))

watch(preset, (valor) => {
  const novo = periodoDoPreset(valor)
  if (novo) {
    periodo.value = novo
    void carregar()
  }
})

const rotuloPeriodo = computed(() =>
  periodo.value.inicio === periodo.value.fim
    ? formatarDiaIso(periodo.value.inicio)
    : `${formatarDiaIso(periodo.value.inicio)} a ${formatarDiaIso(periodo.value.fim)}`
)

async function carregar() {
  if (!ehSuperAdmin.value) return
  const invalido = validarPeriodo(periodo.value)
  if (invalido) {
    erro.value = invalido
    return
  }
  carregando.value = true
  erro.value = ''
  try {
    dados.value = await obterFinanceiroPlataforma(periodo.value.inicio, periodo.value.fim)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o financeiro.'
  } finally {
    carregando.value = false
  }
}

onMounted(() => void carregar())

const t = computed(() => dados.value?.totais)
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Receita da plataforma"
      subtitle="Vendas e taxas de todas as casas, por período."
    />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <!-- Periodo -->
      <BaseCard class="space-y-4">
        <SegmentedControl v-model="preset" :options="opcoes" :disabled="carregando" />
        <form
          v-if="preset === 'PERSONALIZADO'"
          class="flex flex-wrap items-end gap-3"
          @submit.prevent="carregar"
        >
          <BaseInput v-model="periodo.inicio" label="De" type="date" />
          <BaseInput v-model="periodo.fim" label="Até" type="date" />
          <button
            type="submit"
            :disabled="carregando"
            class="inline-flex items-center gap-2 rounded-lg bg-amber-400 px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-zinc-950 transition-colors hover:bg-amber-300 disabled:opacity-50"
          >
            Aplicar
          </button>
        </form>
        <div class="flex items-center justify-between gap-3 text-xs text-zinc-500">
          <span>Período: <strong class="text-zinc-300">{{ rotuloPeriodo }}</strong></span>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 uppercase tracking-wide hover:text-zinc-300"
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

      <!-- Totais -->
      <div v-if="t" class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4" :class="carregando ? 'opacity-60' : ''">
        <DashboardMetricCard
          :icon="CurrencyDollarIcon"
          label="Sua receita (taxas)"
          :value="formatMoeda(t.taxaPlataforma)"
          :subtitle="`${formatNumero(t.ingressosOnline)} ingressos online`"
          value-class="text-amber-300"
        />
        <DashboardMetricCard
          :icon="BanknotesIcon"
          label="Vendido online"
          :value="formatMoeda(t.brutoOnline)"
          :subtitle="`${formatNumero(t.pedidosOnline)} pedidos pagos no Pix`"
        />
        <DashboardMetricCard
          :icon="BuildingStorefrontIcon"
          label="Repassado às casas"
          :value="formatMoeda(t.repasseProdutores)"
          :subtitle="`${formatNumero(t.casasComVendas)} casa(s) com vendas`"
        />
        <DashboardMetricCard
          :icon="TicketIcon"
          label="Vendas na porta (dinheiro)"
          :value="formatMoeda(t.brutoDinheiro)"
          :subtitle="`${formatNumero(t.ingressosDinheiro)} ingressos, sem taxa`"
        />
      </div>

      <!-- Por casa -->
      <BaseCard v-if="dados" :padded="false" class="overflow-hidden">
        <div class="border-b border-zinc-800 p-5">
          <h2 class="text-sm font-semibold text-white">Por casa</h2>
          <p class="mt-1 text-xs text-zinc-500">Ordenado pela taxa gerada no período.</p>
        </div>

        <p v-if="dados.casas.length === 0" class="p-5 text-sm text-zinc-500">
          Nenhuma venda paga neste período.
        </p>

        <template v-else>
          <!-- Desktop -->
          <div class="hidden overflow-x-auto md:block">
            <table class="w-full text-left text-sm">
              <thead class="text-[11px] uppercase tracking-wide text-zinc-500">
                <tr>
                  <th class="px-5 py-3 font-medium">Casa</th>
                  <th class="px-5 py-3 text-right font-medium">Ingressos online</th>
                  <th class="px-5 py-3 text-right font-medium">Vendido online</th>
                  <th class="px-5 py-3 text-right font-medium">Sua taxa</th>
                  <th class="px-5 py-3 text-right font-medium">Casa recebe</th>
                  <th class="px-5 py-3 text-right font-medium">Porta (dinheiro)</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-800">
                <tr v-for="c in dados.casas" :key="c.organizacaoId" class="text-zinc-300">
                  <td class="px-5 py-3">
                    <p class="font-semibold text-white">{{ c.nome }}</p>
                    <p class="text-xs text-zinc-500">/{{ c.slug }} · {{ formatNumero(c.pedidosOnline) }} pedido(s)</p>
                  </td>
                  <td class="px-5 py-3 text-right">{{ formatNumero(c.ingressosOnline) }}</td>
                  <td class="px-5 py-3 text-right">{{ formatMoeda(c.brutoOnline) }}</td>
                  <td class="px-5 py-3 text-right font-semibold text-amber-300">{{ formatMoeda(c.taxaPlataforma) }}</td>
                  <td class="px-5 py-3 text-right">{{ formatMoeda(c.repasseProdutor) }}</td>
                  <td class="px-5 py-3 text-right text-zinc-400">
                    {{ formatMoeda(c.brutoDinheiro) }}
                    <span class="block text-xs text-zinc-600">{{ formatNumero(c.ingressosDinheiro) }} ingr.</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Mobile -->
          <ul class="divide-y divide-zinc-800 md:hidden">
            <li v-for="c in dados.casas" :key="c.organizacaoId" class="space-y-2 p-5">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate font-semibold text-white">{{ c.nome }}</p>
                  <p class="text-xs text-zinc-500">{{ formatNumero(c.ingressosOnline) }} ingressos online</p>
                </div>
                <p class="shrink-0 text-right font-semibold text-amber-300">{{ formatMoeda(c.taxaPlataforma) }}</p>
              </div>
              <div class="grid grid-cols-3 gap-2 text-xs">
                <div>
                  <p class="text-zinc-500">Online</p>
                  <p class="text-zinc-200">{{ formatMoeda(c.brutoOnline) }}</p>
                </div>
                <div>
                  <p class="text-zinc-500">Casa recebe</p>
                  <p class="text-zinc-200">{{ formatMoeda(c.repasseProdutor) }}</p>
                </div>
                <div>
                  <p class="text-zinc-500">Porta</p>
                  <p class="text-zinc-200">{{ formatMoeda(c.brutoDinheiro) }}</p>
                </div>
              </div>
            </li>
          </ul>
        </template>
      </BaseCard>

      <p class="text-xs leading-relaxed text-zinc-500">
        Considera pedidos pagos no período (data do pagamento, horário de Brasília). "Casa recebe" é o valor antes
        da tarifa do Mercado Pago (cerca de 0,99% no Pix). A sua taxa cai na conta Mercado Pago da plataforma como
        "a receber" e é liberada no prazo da conta (hoje, cerca de 14 dias).
      </p>
    </template>
  </div>
</template>
