<script setup lang="ts">
import { computed } from 'vue'
import { Bars3Icon } from '@heroicons/vue/24/outline'

import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { iniciais } from '~/utils/marca'

withDefaults(
  defineProps<{
    title?: string
    expanded?: boolean
  }>(),
  {
    title: '',
    expanded: false
  }
)

const emit = defineEmits<{
  'open-menu': []
}>()

const { operador } = useOperatorAuth()
const sigla = computed(() => iniciais(operador.value?.organizacao?.nome ?? operador.value?.nome))
</script>

<template>
  <header
    class="flex min-h-16 shrink-0 items-center gap-3 border-b border-zinc-800 bg-zinc-950 px-4 pt-[env(safe-area-inset-top)] lg:hidden"
  >
    <button
      type="button"
      aria-label="Abrir menu"
      :aria-expanded="expanded"
      aria-controls="admin-mobile-drawer"
      class="flex h-11 w-11 shrink-0 cursor-pointer items-center justify-center rounded-lg border border-zinc-700 text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click="emit('open-menu')"
    >
      <Bars3Icon class="h-6 w-6" />
    </button>

    <span class="shrink-0 text-base font-bold tracking-tight text-white">Ingressoudi<span class="text-amber-400">.</span></span>

    <span v-if="title" class="min-w-0 truncate text-sm font-semibold text-zinc-300">
      {{ title }}
    </span>

    <span
      class="ml-auto flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-amber-400/50 bg-zinc-800 text-xs font-semibold text-amber-400"
    >
      {{ sigla }}
    </span>
  </header>
</template>
