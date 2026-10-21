<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { Component } from 'vue'
import {
  ArrowRightOnRectangleIcon,
  BanknotesIcon,
  BuildingOffice2Icon,
  CalendarDaysIcon,
  ChartBarIcon,
  FunnelIcon,
  GlobeAltIcon,
  PresentationChartLineIcon,
  Cog6ToothIcon,
  QrCodeIcon,
  RectangleStackIcon,
  Squares2X2Icon,
  TicketIcon,
  UserGroupIcon,
  UsersIcon,
  XMarkIcon
} from '@heroicons/vue/24/outline'
import { useRoute } from '#imports'

import InstalarAppBotao from '~/components/InstalarAppBotao.vue'
import SidebarItem from '~/components/SidebarItem.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  PERFIS_ADMIN,
  PERFIS_ADMIN_PORTARIA,
  listaVipLiberada,
  podeVerItemSidebar,
  type PerfilSidebar
} from '~/utils/navegacao'

const props = withDefaults(
  defineProps<{
    mobile?: boolean
  }>(),
  { mobile: false }
)

const emit = defineEmits<{
  close: []
  navigate: []
}>()

interface NavItem {
  to: string
  icon: Component
  label: string
  allowedProfiles: PerfilSidebar[]
}

const route = useRoute()

const { user, operador, carregado, carregarOperador, trocarOrganizacao, logout } = useOperatorAuth()

const trocando = ref(false)
const erroTroca = ref('')

async function aoTrocarOrganizacao(evento: Event) {
  const id = (evento.target as HTMLSelectElement).value
  if (!id || id === operador.value?.organizacao?.id) return
  trocando.value = true
  erroTroca.value = ''
  try {
    const perfil = await trocarOrganizacao(id)
    // recarrega a aplicacao para nao manter dados da organizacao anterior em memoria
    window.location.assign(perfil?.perfil === 'PORTARIA' ? '/portaria' : '/painel')
  } catch {
    erroTroca.value = 'Não foi possível trocar de organização.'
    trocando.value = false
  }
}

onMounted(() => {
  if (user.value && !operador.value) {
    void carregarOperador()
  }
})

async function sair() {
  await logout()
  await navigateTo('/login')
}

const activeLabel = computed(() => {
  const meta = route.meta.sidebarActive
  return typeof meta === 'string' ? meta : 'Dashboard'
})

const itens: NavItem[] = [
  { to: '/painel', icon: Squares2X2Icon, label: 'Dashboard', allowedProfiles: PERFIS_ADMIN },
  { to: '/eventos', icon: CalendarDaysIcon, label: 'Eventos', allowedProfiles: PERFIS_ADMIN },
  { to: '/pedidos', icon: RectangleStackIcon, label: 'Pedidos', allowedProfiles: PERFIS_ADMIN },
  { to: '/ingressos', icon: TicketIcon, label: 'Ingressos', allowedProfiles: PERFIS_ADMIN },
  { to: '/lista-vip', icon: UserGroupIcon, label: 'Lista VIP', allowedProfiles: PERFIS_ADMIN },
  {
    to: '/entradas',
    icon: ArrowRightOnRectangleIcon,
    label: 'Entradas',
    allowedProfiles: PERFIS_ADMIN
  },
  {
    to: '/portaria',
    icon: QrCodeIcon,
    label: 'Portaria',
    allowedProfiles: PERFIS_ADMIN_PORTARIA
  },
  { to: '#', icon: UsersIcon, label: 'Participantes', allowedProfiles: PERFIS_ADMIN },
  { to: '/financeiro', icon: BanknotesIcon, label: 'Financeiro', allowedProfiles: PERFIS_ADMIN },
  { to: '#', icon: ChartBarIcon, label: 'Relatórios', allowedProfiles: PERFIS_ADMIN },
  {
    to: '/configuracoes',
    icon: Cog6ToothIcon,
    label: 'Configurações',
    allowedProfiles: PERFIS_ADMIN
  }
]

const perfil = computed<PerfilSidebar | null>(() => operador.value?.perfil ?? null)
// Enquanto o perfil nao estiver resolvido, nao liberar nenhum item (evita flash
// do menu administrativo para PORTARIA).
const perfilResolvido = computed(() => carregado.value && perfil.value !== null)
const items = computed(() => {
  if (!perfilResolvido.value) return []
  const visiveis = itens.filter(
    (item) =>
      podeVerItemSidebar(item, perfil.value) && (item.to !== '/lista-vip' || listaVipLiberada(operador.value))
  )
  if (operador.value?.superAdmin) {
    visiveis.push({
      to: '/plataforma/organizacoes',
      icon: BuildingOffice2Icon,
      label: 'Organizações',
      allowedProfiles: PERFIS_ADMIN_PORTARIA
    })
    visiveis.push({
      to: '/plataforma/eventos',
      icon: GlobeAltIcon,
      label: 'Todos os eventos',
      allowedProfiles: PERFIS_ADMIN_PORTARIA
    })
    visiveis.push({
      to: '/plataforma/financeiro',
      icon: PresentationChartLineIcon,
      label: 'Receita da plataforma',
      allowedProfiles: PERFIS_ADMIN_PORTARIA
    })
    visiveis.push({
      to: '/plataforma/crm',
      icon: FunnelIcon,
      label: 'CRM comercial',
      allowedProfiles: PERFIS_ADMIN_PORTARIA
    })
  }
  return visiveis
})

const raizClasses = computed(() =>
  props.mobile
    ? 'flex h-full w-full flex-col overflow-y-auto bg-zinc-950 p-5'
    : 'w-72 shrink-0 flex-col overflow-y-auto border-r border-zinc-800 bg-zinc-950 p-5'
)
</script>

<template>
  <aside :class="raizClasses">
    <div class="relative mb-8 flex items-center justify-center">
      <p class="text-xl font-bold tracking-tight text-white">Ingressoudi<span class="text-amber-400">.</span></p>
      <button
        v-if="props.mobile"
        type="button"
        aria-label="Fechar menu"
        class="absolute right-0 top-1/2 flex h-10 w-10 -translate-y-1/2 cursor-pointer items-center justify-center rounded-lg border border-zinc-700 text-zinc-400 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        @click="emit('close')"
      >
        <XMarkIcon class="h-5 w-5" />
      </button>
    </div>

    <nav class="flex flex-1 flex-col gap-1.5">
      <SidebarItem
        v-for="item in items"
        :key="item.label"
        :to="item.to"
        :icon="item.icon"
        :label="item.label"
        :active="item.label === activeLabel"
        size="lg"
        @click="emit('navigate')"
      />
      <InstalarAppBotao variante="sidebar" />
    </nav>

    <div v-if="operador" class="mt-5 rounded-xl border border-zinc-800 bg-zinc-900 p-4">
      <p class="truncate text-sm font-semibold text-white">{{ operador.nome }}</p>
      <p class="truncate text-xs text-zinc-500">{{ operador.email }}</p>
      <div v-if="operador.organizacao" class="mt-3">
        <p class="text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Organização</p>
        <select
          v-if="operador.organizacoes.length > 1"
          :value="operador.organizacao.id"
          :disabled="trocando"
          aria-label="Trocar de organização"
          class="mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-2.5 py-1.5 text-xs text-white focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30 disabled:opacity-50"
          @change="aoTrocarOrganizacao"
        >
          <option v-for="org in operador.organizacoes" :key="org.id" :value="org.id">
            {{ org.nome }}
          </option>
        </select>
        <p v-else class="mt-0.5 truncate text-xs font-semibold text-zinc-200">
          {{ operador.organizacao.nome }}
        </p>
        <p v-if="erroTroca" class="mt-1 text-xs text-red-400">{{ erroTroca }}</p>
      </div>
      <span
        class="mt-2 inline-flex items-center rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
      >
        {{ operador.perfil }}
      </span>
      <button
        type="button"
        class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-zinc-700 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        @click="sair"
      >
        <ArrowRightOnRectangleIcon class="h-4 w-4" />
        Sair
      </button>
    </div>
  </aside>
</template>
