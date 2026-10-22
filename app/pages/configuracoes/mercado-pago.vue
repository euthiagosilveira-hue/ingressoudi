<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'
import { BanknotesIcon, CheckCircleIcon, ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import {
  desconectarMercadoPago,
  obterStatusMercadoPago,
  type StatusMercadoPago
} from '~/services/admin/mercadoPago'
import { formatData, formatMoeda } from '~/utils/format'

definePageMeta({
  title: 'Mercado Pago',
  description: 'Conecte a conta Mercado Pago que recebe as vendas Pix.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth', 'sem-modo-suporte']
})

const route = useRoute()

const MENSAGENS: Record<string, { tipo: 'ok' | 'erro'; texto: string }> = {
  conectado: { tipo: 'ok', texto: 'Conta Mercado Pago conectada com sucesso.' },
  erro: { tipo: 'erro', texto: 'Não foi possível conectar o Mercado Pago. Tente novamente.' },
  expirado: { tipo: 'erro', texto: 'A autorização demorou demais. Clique em Conectar de novo.' },
  'sem-permissao': { tipo: 'erro', texto: 'Apenas administradores da organização podem conectar o Mercado Pago.' },
  'organizacao-trocada': { tipo: 'erro', texto: 'A organização ativa mudou durante a conexão. Tente novamente.' },
  indisponivel: { tipo: 'erro', texto: 'A integração com o Mercado Pago ainda não está configurada na plataforma.' }
}

const aviso = computed(() => MENSAGENS[String(route.query.status ?? '')] ?? null)

const carregando = ref(true)
const erro = ref('')
const status = ref<StatusMercadoPago | null>(null)
const desconectando = ref(false)

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    status.value = await obterStatusMercadoPago()
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o Mercado Pago.'
  } finally {
    carregando.value = false
  }
}

async function desconectar() {
  if (desconectando.value) return
  if (!window.confirm('Desconectar a conta? As vendas Pix ficam indisponíveis até conectar de novo.')) return
  desconectando.value = true
  try {
    await desconectarMercadoPago()
    toast.success('Conta Mercado Pago desconectada.')
    await carregar()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível desconectar.')
  } finally {
    desconectando.value = false
  }
}

onMounted(() => void carregar())
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Mercado Pago"
      subtitle="As vendas Pix caem direto na conta Mercado Pago da sua organização."
    >
      <template #actions>
        <AppButton to="/configuracoes" size="sm">Voltar</AppButton>
      </template>
    </PageHeader>

    <p
      v-if="aviso"
      role="status"
      class="rounded-xl border p-3 text-sm"
      :class="aviso.tipo === 'ok' ? 'border-green-500/40 bg-green-500/10 text-green-200' : 'border-red-500/40 bg-red-500/10 text-red-200'"
    >
      {{ aviso.texto }}
    </p>

    <div v-if="carregando" class="h-40 animate-pulse rounded-2xl border border-zinc-800 bg-zinc-900" />

    <BaseCard v-else-if="erro">
      <p class="text-sm text-red-300">{{ erro }}</p>
      <AppButton class="mt-3" size="sm" @click="carregar">Tentar novamente</AppButton>
    </BaseCard>

    <template v-else-if="status">
      <BaseCard>
        <div class="flex items-start gap-3">
          <span
            class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950"
            :class="status.conectado ? 'text-green-300' : 'text-amber-400'"
          >
            <CheckCircleIcon v-if="status.conectado" class="h-6 w-6" />
            <ExclamationTriangleIcon v-else class="h-6 w-6" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-white">
              {{ status.conectado ? 'Conta conectada' : 'Nenhuma conta conectada' }}
            </p>
            <p v-if="status.conectado" class="mt-1 text-xs text-zinc-400">
              ID da conta: {{ status.mpUserId }}
              <span v-if="status.liveMode === false"> · modo de teste</span>
              <span v-if="status.conectadoEm"> · conectada em {{ formatData(status.conectadoEm) }}</span>
            </p>
            <p v-else class="mt-1 text-xs text-zinc-400">
              Sem conta conectada, os compradores não conseguem pagar com Pix nos seus eventos.
            </p>
          </div>
        </div>

        <div class="mt-5 flex flex-wrap items-center gap-3">
          <!-- Link externo (rota de servidor): recarrega a pagina e vai para o Mercado Pago -->
          <a
            href="/api/mercadopago/oauth/iniciar"
            class="inline-flex items-center justify-center gap-2 rounded-lg bg-amber-400 px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-zinc-950 transition-colors hover:bg-amber-300"
          >
            {{ status.conectado ? 'Reconectar' : 'Conectar Mercado Pago' }}
          </a>
          <AppButton v-if="status.conectado" variant="danger" :disabled="desconectando" @click="desconectar">
            {{ desconectando ? 'Desconectando...' : 'Desconectar' }}
          </AppButton>
        </div>
      </BaseCard>

      <BaseCard>
        <div class="flex items-start gap-3">
          <span
            class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400"
          >
            <BanknotesIcon class="h-6 w-6" />
          </span>
          <div>
            <p class="text-sm font-semibold text-white">
              Taxa de serviço: {{ formatMoeda(status.taxaServico) }} por ingresso
            </p>
            <p class="mt-1 text-xs text-zinc-400">
              Descontada automaticamente pelo Mercado Pago em cada venda Pix. Em cada evento você
              escolhe se repassa a taxa ao comprador ou se absorve. Vendas em dinheiro não têm taxa.
            </p>
          </div>
        </div>
      </BaseCard>
    </template>
  </div>
</template>
