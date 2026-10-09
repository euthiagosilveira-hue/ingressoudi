<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute } from '#imports'

import AdminMobileHeader from '~/components/AdminMobileHeader.vue'
import AdminSidebar from '~/components/AdminSidebar.vue'

const props = withDefaults(
  defineProps<{
    title?: string
  }>(),
  { title: '' }
)

const route = useRoute()
const sidebarOpen = ref(false)

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

      <header v-if="$slots.header" class="hidden shrink-0 lg:block">
        <slot name="header" />
      </header>

      <main class="flex-1 space-y-6 overflow-y-auto p-5 sm:p-8">
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
