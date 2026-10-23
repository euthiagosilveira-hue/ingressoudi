<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ArrowPathIcon, BellAlertIcon, BuildingStorefrontIcon, ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import PushNotificacoesCard from '~/components/plataforma/PushNotificacoesCard.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { listarErrosPagamento } from '~/services/admin/errosPagamento'
import {
  ROTULOS_TIPO_ERRO,
  contarPorTipo,
  filtrarErrosPagamento,
  rotuloTipoErro,
  textoDetalhe,
  type ErroPagamento,
  type PeriodoErros
} from '~/utils/errosPagamento'
import { formatDataHora, formatNumero } from '~/utils/format'

definePageMeta({
  title: 'Erros de pagamento',
  description: 'Falhas de pagamento de todas as casas da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Erros de pagamento',
  middleware: ['operator-auth']
})

const { operador } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const erros = ref<ErroPagamento[]>([])
const carregando = ref(false)
const erro = ref('')

const tipo = ref('')
const periodo = ref<PeriodoErros>('7D')

const opcoesPeriodo = [
  { value: '24H', label: 'Últimas 24h' },
  { value: '7D', label: '7 dias' },
  { value: 'TODOS', label: 'Todos' }
]
const opcoesTipo = [
  { value: '', label: 'Todos os tipos' },
  ...Object.entries(ROTULOS_TIPO_ERRO).map(([value, label]) => ({ value, label }))
]

const lista = computed(() => filtrarErrosPagamento(erros.value, { tipo: tipo.value, periodo: periodo.value }, Date.now()))
const porTipo = computed(() => contarPorTipo(lista.value))

async function carregar() {
  if (!ehSuperAdmin.value) return
  carregando.value = true
  erro.value = ''
  try {
    erros.value = await listarErrosPagamento()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os erros de pagamento.'
  } finally {
    carregando.value = false
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Erros de pagamento"
      subtitle="Falhas no Pix, nos avisos e na conexão do Mercado Pago e nos reembolsos, de todas as casas."
    />

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <PushNotificacoesCard />

      <BaseCard class="space-y-4">
        <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <SegmentedControl v-model="periodo" :options="opcoesPeriodo" :disabled="carregando" />
          <div class="flex items-center gap-3">
            <BaseSelect v-model="tipo" :options="opcoesTipo" class="md:w-64" />
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
        </div>
        <div v-if="porTipo.length" class="flex flex-wrap gap-2">
          <span
            v-for="t in porTipo"
            :key="t.tipo"
            class="inline-flex items-center gap-1.5 rounded-full border border-red-500/30 px-2.5 py-0.5 text-xs text-red-300"
          >
            {{ rotuloTipoErro(t.tipo) }} · {{ formatNumero(t.total) }}
          </span>
        </div>
      </BaseCard>

      <p
        v-if="erro"
        role="alert"
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        {{ erro }}
      </p>

      <BaseCard :padded="false" class="overflow-hidden">
        <div v-if="carregando && erros.length === 0" class="space-y-3 p-5" aria-busy="true">
          <div v-for="i in 3" :key="i" class="h-14 animate-pulse rounded-xl bg-zinc-800/60" />
        </div>

        <p v-else-if="lista.length === 0" class="p-5 text-sm text-zinc-500">
          Nenhum erro de pagamento neste período. Tudo certo.
        </p>

        <ul v-else class="divide-y divide-zinc-800">
          <li v-for="e in lista" :key="e.id" class="flex gap-3 p-5">
            <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0 text-red-400" />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span class="text-sm font-semibold text-white">{{ rotuloTipoErro(e.tipo) }}</span>
                <span class="text-xs text-zinc-500">{{ formatDataHora(e.criadoEm) }}</span>
                <span v-if="e.avisado" class="inline-flex items-center gap-1 text-[11px] text-amber-300/90">
                  <BellAlertIcon class="h-3.5 w-3.5" /> avisado
                </span>
              </div>
              <p class="mt-1 text-sm text-zinc-300">{{ e.mensagem }}</p>
              <p v-if="e.organizacaoNome" class="mt-1 flex items-center gap-1.5 text-xs text-amber-300/90">
                <BuildingStorefrontIcon class="h-3.5 w-3.5 shrink-0" />
                {{ e.organizacaoNome }}
              </p>
              <p v-if="e.referencia" class="mt-1 break-all text-xs text-zinc-500">Referência: {{ e.referencia }}</p>
              <p v-if="textoDetalhe(e.detalhe)" class="mt-1 break-all font-mono text-[11px] text-zinc-600">
                {{ textoDetalhe(e.detalhe) }}
              </p>
            </div>
          </li>
        </ul>
      </BaseCard>

      <p class="text-xs leading-relaxed text-zinc-500">
        Todo erro fica registrado aqui. O aviso no celular sai no máximo uma vez a cada 15 minutos para o mesmo
        tipo de erro da mesma casa, para não lotar de notificações.
      </p>
    </template>
  </div>
</template>
