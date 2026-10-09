<script setup lang="ts">
import { computed, onMounted } from 'vue'
import type { Component } from 'vue'
import {
  ArrowRightOnRectangleIcon,
  BanknotesIcon,
  CalendarDaysIcon,
  ChartBarIcon,
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

import SidebarItem from '~/components/SidebarItem.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  PERFIS_ADMIN,
  PERFIS_ADMIN_PORTARIA,
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

const { user, operador, carregado, carregarOperador, logout } = useOperatorAuth()

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
  { to: '/', icon: Squares2X2Icon, label: 'Dashboard', allowedProfiles: PERFIS_ADMIN },
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
const items = computed(() =>
  perfilResolvido.value ? itens.filter((item) => podeVerItemSidebar(item, perfil.value)) : []
)

const raizClasses = computed(() =>
  props.mobile
    ? 'flex h-full w-full flex-col overflow-y-auto bg-zinc-950 p-5'
    : 'w-72 shrink-0 flex-col overflow-y-auto border-r border-zinc-800 bg-zinc-950 p-5'
)
</script>

<template>
  <aside :class="raizClasses">
    <div class="relative mb-8 flex items-center justify-center">
      <img src="/Logo horizontal.png" alt="Galeria Zero 1" class="h-11 w-auto" />
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
    </nav>

    <div v-if="operador" class="mt-5 rounded-xl border border-zinc-800 bg-zinc-900 p-4">
      <p class="truncate text-sm font-semibold text-white">{{ operador.nome }}</p>
      <p class="truncate text-xs text-zinc-500">{{ operador.email }}</p>
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
