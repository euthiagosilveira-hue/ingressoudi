<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import {
  ArrowDownTrayIcon,
  ArrowPathIcon,
  ArrowTopRightOnSquareIcon,
  BuildingStorefrontIcon,
  ClipboardDocumentIcon,
  EnvelopeIcon,
  MagnifyingGlassIcon,
  UserCircleIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import PageHeader from '~/components/PageHeader.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { listarDonosPlataforma } from '~/services/admin/donosPlataforma'
import {
  filtrarCasasComDono,
  gerarCsvDonos,
  type CasaComDono,
  type SituacaoCasa
} from '~/utils/donosPlataforma'
import { formatDataHoraCompleta, formatDataNumerica, formatNumero } from '~/utils/format'
import { rotaOrganizacao } from '~/utils/rotasPublicas'

definePageMeta({
  title: 'Donos das casas',
  description: 'Quem cadastrou cada casa da plataforma.',
  layout: 'admin-layout',
  sidebarActive: 'Donos das casas',
  middleware: ['operator-auth']
})

const { operador } = useOperatorAuth()
const ehSuperAdmin = computed(() => Boolean(operador.value?.superAdmin))

const casas = ref<CasaComDono[]>([])
const carregando = ref(false)
const erro = ref('')

const busca = ref('')
const situacao = ref<SituacaoCasa>('TODAS')

const opcoesSituacao = [
  { value: 'TODAS', label: 'Todas' },
  { value: 'AGUARDANDO', label: 'Aguardando aprovação' },
  { value: 'APROVADAS', label: 'Aprovadas' },
  { value: 'SEM_MERCADO_PAGO', label: 'Sem Mercado Pago' }
]

const lista = computed(() => filtrarCasasComDono(casas.value, busca.value, situacao.value))

async function carregar() {
  if (!ehSuperAdmin.value) return
  carregando.value = true
  erro.value = ''
  try {
    casas.value = await listarDonosPlataforma()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar os donos das casas.'
  } finally {
    carregando.value = false
  }
}

async function copiarEmail(email: string) {
  try {
    await navigator.clipboard.writeText(email)
    toast.success('E-mail copiado.')
  } catch {
    toast.error('Não foi possível copiar o e-mail.')
  }
}

function exportarCsv() {
  // BOM para o Excel reconhecer os acentos.
  const blob = new Blob(['﻿' + gerarCsvDonos(lista.value)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `donos-das-casas-${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

function situacaoCasa(c: CasaComDono): { texto: string; classe: string } {
  if (!c.ativo) return { texto: 'Desativada', classe: 'border-zinc-700 text-zinc-500' }
  if (!c.aprovada) return { texto: 'Aguardando aprovação', classe: 'border-amber-400/40 text-amber-300' }
  return { texto: 'Aprovada', classe: 'border-green-500/30 text-green-300' }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Donos das casas" subtitle="Quem cadastrou cada casa e como está a conta.">
      <template v-if="ehSuperAdmin" #actions>
        <AppButton size="sm" :disabled="carregando || lista.length === 0" @click="exportarCsv">
          <ArrowDownTrayIcon class="h-4 w-4" />
          Exportar planilha
        </AppButton>
      </template>
    </PageHeader>

    <BaseCard v-if="!ehSuperAdmin">
      <p class="text-sm text-zinc-400">Apenas o super administrador da plataforma acessa esta área.</p>
    </BaseCard>

    <template v-else>
      <!-- Filtros -->
      <BaseCard class="space-y-4">
        <div class="relative">
          <BaseInput v-model="busca" placeholder="Buscar por casa, nome ou e-mail do dono" />
          <MagnifyingGlassIcon class="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500" />
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

      <p class="text-sm text-zinc-500">{{ formatNumero(lista.length) }} casa(s)</p>

      <!-- Lista -->
      <BaseCard :padded="false" class="overflow-hidden">
        <div v-if="carregando && casas.length === 0" class="space-y-3 p-5" aria-busy="true">
          <div v-for="i in 3" :key="i" class="h-20 animate-pulse rounded-xl bg-zinc-800/60" />
        </div>

        <p v-else-if="lista.length === 0" class="p-5 text-sm text-zinc-500">
          Nenhuma casa encontrada com esses filtros.
        </p>

        <ul v-else class="divide-y divide-zinc-800">
          <li v-for="c in lista" :key="c.organizacaoId" class="grid gap-4 p-5 lg:grid-cols-[1fr_1.2fr_15rem]">
            <!-- Casa -->
            <div class="min-w-0">
              <p class="flex items-center gap-1.5 truncate font-semibold text-white">
                <BuildingStorefrontIcon class="h-4 w-4 shrink-0 text-amber-400" />
                {{ c.organizacaoNome }}
              </p>
              <a
                :href="rotaOrganizacao(c.organizacaoSlug)"
                target="_blank"
                rel="noopener"
                class="mt-0.5 inline-flex items-center gap-1 truncate text-xs text-zinc-500 hover:text-amber-400"
              >
                /{{ c.organizacaoSlug }}
                <ArrowTopRightOnSquareIcon class="h-3 w-3" />
              </a>
              <div class="mt-2 flex flex-wrap items-center gap-1.5">
                <span
                  class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
                  :class="situacaoCasa(c).classe"
                >
                  {{ situacaoCasa(c).texto }}
                </span>
                <span
                  class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
                  :class="c.mercadoPagoConectado ? 'border-sky-400/30 text-sky-300' : 'border-red-500/30 text-red-300'"
                >
                  {{ c.mercadoPagoConectado ? 'Mercado Pago conectado' : 'Sem Mercado Pago' }}
                </span>
              </div>
              <p class="mt-2 text-xs text-zinc-600">Criada em {{ formatDataNumerica(c.criadoEm) }}</p>
            </div>

            <!-- Dono -->
            <div class="min-w-0">
              <template v-if="c.dono">
                <p class="flex items-center gap-1.5 truncate text-sm font-medium text-zinc-100">
                  <UserCircleIcon class="h-4 w-4 shrink-0 text-zinc-500" />
                  {{ c.dono.nome }}
                  <span v-if="!c.dono.ativo" class="text-xs font-normal text-red-300">(conta desativada)</span>
                </p>
                <div class="mt-1 flex items-center gap-2">
                  <a :href="`mailto:${c.dono.email}`" class="truncate text-sm text-amber-300 hover:underline">
                    {{ c.dono.email }}
                  </a>
                  <button
                    type="button"
                    class="shrink-0 rounded p-1 text-zinc-500 hover:bg-zinc-800 hover:text-zinc-200"
                    :aria-label="`Copiar e-mail de ${c.dono.nome}`"
                    @click="copiarEmail(c.dono.email)"
                  >
                    <ClipboardDocumentIcon class="h-4 w-4" />
                  </button>
                </div>
                <dl class="mt-2 grid grid-cols-1 gap-x-4 gap-y-1 text-xs sm:grid-cols-2">
                  <div>
                    <dt class="inline text-zinc-500">E-mail confirmado:</dt>
                    <dd class="inline" :class="c.dono.emailConfirmado ? 'text-zinc-300' : 'text-amber-300'">
                      {{ c.dono.emailConfirmado ? 'sim' : 'não' }}
                    </dd>
                  </div>
                  <div>
                    <dt class="inline text-zinc-500">Último acesso:</dt>
                    <dd class="inline text-zinc-300">
                      {{ c.dono.ultimoAcessoEm ? formatDataHoraCompleta(c.dono.ultimoAcessoEm) : 'nunca' }}
                    </dd>
                  </div>
                  <div>
                    <dt class="inline text-zinc-500">Termos:</dt>
                    <dd class="inline text-zinc-300">
                      {{ c.dono.termosAceitosEm
                        ? `versão ${c.dono.termosVersao ?? '?'} em ${formatDataNumerica(c.dono.termosAceitosEm)}`
                        : 'não registrado' }}
                    </dd>
                  </div>
                  <div v-if="c.dono.outrasCasas > 0">
                    <dt class="inline text-zinc-500">Outras casas:</dt>
                    <dd class="inline text-zinc-300">{{ formatNumero(c.dono.outrasCasas) }}</dd>
                  </div>
                </dl>
              </template>
              <p v-else class="text-sm text-zinc-500">Nenhum administrador ativo nesta casa.</p>

              <p v-if="c.outrosAdministradores.length" class="mt-2 flex items-start gap-1.5 text-xs text-zinc-500">
                <EnvelopeIcon class="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span class="break-all">
                  Outros administradores: {{ c.outrosAdministradores.map((a) => a.email).join(', ') }}
                </span>
              </p>
            </div>

            <!-- Atividade -->
            <div class="grid grid-cols-3 gap-3 text-xs lg:grid-cols-1 lg:gap-1">
              <div class="lg:flex lg:justify-between">
                <p class="text-zinc-500">Eventos</p>
                <p class="text-sm font-semibold text-white">{{ formatNumero(c.eventos) }}</p>
              </div>
              <div class="lg:flex lg:justify-between">
                <p class="text-zinc-500">Ingressos vendidos</p>
                <p class="text-sm font-semibold text-white">{{ formatNumero(c.ingressosVendidos) }}</p>
              </div>
              <div class="lg:flex lg:justify-between">
                <p class="text-zinc-500">Equipe</p>
                <p class="text-sm font-semibold text-white">{{ formatNumero(c.equipe) }}</p>
              </div>
            </div>
          </li>
        </ul>
      </BaseCard>

      <p class="text-xs leading-relaxed text-zinc-500">
        Dono é quem cadastrou a casa. Quando não há esse registro, aparece o administrador mais antigo dela.
        Estes dados são pessoais: use só para suporte e contato com a casa.
      </p>
    </template>
  </div>
</template>
