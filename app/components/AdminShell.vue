<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute } from '#imports'
import { ClockIcon, LifebuoyIcon } from '@heroicons/vue/24/outline'

import AdminMobileHeader from '~/components/AdminMobileHeader.vue'
import AdminSidebar from '~/components/AdminSidebar.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'

const props = withDefaults(
  defineProps<{
    title?: string
  }>(),
  { title: '' }
)

const route = useRoute()
const sidebarOpen = ref(false)
const { operador, sairModoSuporte } = useOperatorAuth()

// Super admin dentro de uma casa da qual nao e membro.
const modoSuporte = computed(() => Boolean(operador.value?.modoSuporte))
// Casa cadastrada pelo produtor aguardando aprovacao da plataforma.
const casaEmAnalise = computed(() => !modoSuporte.value && operador.value?.organizacao?.aprovada === false)

const saindo = ref(false)
async function aoSairModoSuporte() {
  saindo.value = true
  try {
    await sairModoSuporte()
  } catch {
    saindo.value = false
  }
}

const titulo = computed(() => props.title || String(route.meta.title ?? ''))

function abrirMenu() {
  sidebarOpen.value = true
}

function fecharMenu() {
  sidebarOpen.value = false
}

function aoTeclar(evento: KeyboardEvent) {
  if (evento.key === 'Escape') fecharMenu()
}

let mediaQuery: MediaQueryList | null = null

function aoMudarBreakpoint(evento: MediaQueryListEvent) {
  if (evento.matches) fecharMenu()
}

watch(
  () => route.fullPath,
  () => fecharMenu()
)

watch(sidebarOpen, (aberto) => {
  if (typeof document === 'undefined') return
  if (aberto) {
    document.body.style.overflow = 'hidden'
    document.addEventListener('keydown', aoTeclar)
  } else {
    document.body.style.overflow = ''
    document.removeEventListener('keydown', aoTeclar)
  }
})

onMounted(() => {
  if (typeof window === 'undefined') return
  mediaQuery = window.matchMedia('(min-width: 1024px)')
  mediaQuery.addEventListener('change', aoMudarBreakpoint)
})

onBeforeUnmount(() => {
  if (typeof document !== 'undefined') {
    document.body.style.overflow = ''
    document.removeEventListener('keydown', aoTeclar)
  }
  mediaQuery?.removeEventListener('change', aoMudarBreakpoint)
})
</script>

<template>
  <div class="flex h-[100dvh] overflow-hidden bg-zinc-950 text-white">
    <AdminSidebar class="hidden lg:flex" />

    <div class="flex min-w-0 flex-1 flex-col overflow-hidden">
      <AdminMobileHeader :title="titulo" :expanded="sidebarOpen" @open-menu="abrirMenu" />

      <div
        v-if="modoSuporte"
        role="status"
        class="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-2 border-b border-amber-400/40 bg-amber-400 px-5 py-2.5 text-sm text-zinc-950 sm:px-8"
      >
        <LifebuoyIcon class="h-5 w-5 shrink-0" />
        <p class="min-w-0 flex-1">
          <strong>Modo suporte:</strong> você está em <strong>{{ operador?.organizacao?.nome }}</strong>.
          Tudo o que fizer aqui é real para o produtor.
        </p>
        <button
          type="button"
          class="rounded-lg border border-zinc-950/30 px-3 py-1 text-xs font-semibold hover:bg-zinc-950/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-950/50"
          :disabled="saindo"
          @click="aoSairModoSuporte"
        >
          {{ saindo ? 'Saindo...' : 'Sair do modo suporte' }}
        </button>
      </div>

      <header v-if="$slots.header" class="hidden shrink-0 lg:block">
        <slot name="header" />
      </header>

      <main class="flex-1 space-y-6 overflow-y-auto p-5 sm:p-8">
        <div
          v-if="casaEmAnalise"
          role="status"
          class="flex items-start gap-3 rounded-xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-100"
        >
          <ClockIcon class="mt-0.5 h-5 w-5 shrink-0 text-amber-400" />
          <p>
            <strong class="text-amber-300">Sua casa está em análise.</strong>
            Enquanto isso, conecte o Mercado Pago, personalize sua página e crie eventos como rascunho.
            A publicação é liberada assim que a plataforma aprovar seu cadastro.
          </p>
        </div>
        <slot />
      </main>
    </div>

    <!-- Drawer mobile -->
    <div class="lg:hidden">
      <Transition
        enter-active-class="transition-opacity duration-200"
        enter-from-class="opacity-0"
        leave-active-class="transition-opacity duration-200"
        leave-to-class="opacity-0"
      >
        <div
          v-if="sidebarOpen"
          class="fixed inset-0 z-40 bg-black/60"
          aria-hidden="true"
          @click="fecharMenu"
        ></div>
      </Transition>

      <aside
        id="admin-mobile-drawer"
        class="fixed inset-y-0 left-0 z-50 w-72 max-w-[85vw] transform pb-[env(safe-area-inset-bottom)] transition-transform duration-200 ease-out"
        :class="sidebarOpen ? 'translate-x-0' : '-translate-x-full'"
        role="dialog"
        aria-modal="true"
        aria-label="Menu de navegação"
        :inert="!sidebarOpen"
      >
        <AdminSidebar mobile @close="fecharMenu" @navigate="fecharMenu" />
      </aside>
    </div>
  </div>
</template>
