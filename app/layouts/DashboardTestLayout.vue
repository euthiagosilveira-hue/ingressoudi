<script setup lang="ts">
import { computed } from 'vue'
import { CalendarDaysIcon, ChevronDownIcon } from '@heroicons/vue/24/outline'
import { useRoute } from '#imports'

import AdminShell from '~/components/AdminShell.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { iniciais } from '~/utils/marca'

const route = useRoute()
const title = computed(() => String(route.meta.title ?? 'Dashboard'))

const { operador } = useOperatorAuth()
const nomeOrganizacao = computed(() => operador.value?.organizacao?.nome ?? 'Minha organização')
const sigla = computed(() => iniciais(nomeOrganizacao.value))
const perfilRotulo = computed(() => (operador.value?.perfil === 'PORTARIA' ? 'Portaria' : 'Administrador'))
</script>

<template>
  <AdminShell :title="title">
    <template #header>
      <div class="px-5 pt-6 sm:px-8 sm:pt-8">
        <div class="flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-3xl font-bold tracking-tight text-white">{{ title }}</h1>
            <p class="mt-2 text-base text-zinc-400">Visão geral do evento de hoje</p>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <button
              type="button"
              class="flex h-14 cursor-pointer items-center gap-2.5 rounded-xl border border-zinc-700 bg-zinc-900 px-4 text-zinc-200 transition-colors duration-150 hover:border-zinc-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
            >
              <CalendarDaysIcon class="h-5 w-5 shrink-0 text-zinc-400" />
              <span class="hidden text-sm sm:inline">Sábado - 29 de Agosto</span>
              <span class="text-sm sm:hidden">29/08</span>
              <ChevronDownIcon class="h-4 w-4 shrink-0 text-zinc-400" />
            </button>

            <button
              type="button"
              class="flex h-14 cursor-pointer items-center gap-3 rounded-xl border border-zinc-700 bg-zinc-900 p-1.5 pr-3 transition-colors duration-150 hover:border-zinc-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
            >
              <span
                class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border border-amber-400/50 bg-zinc-800 text-sm font-semibold text-amber-400"
              >
                {{ sigla }}
              </span>
              <span class="hidden min-w-0 text-left sm:block">
                <span class="block truncate text-sm font-semibold text-white">{{ nomeOrganizacao }}</span>
                <span class="block truncate text-xs text-zinc-400">{{ perfilRotulo }}</span>
              </span>
              <ChevronDownIcon class="h-4 w-4 shrink-0 text-zinc-400" />
            </button>
          </div>
        </div>
      </div>
    </template>

    <slot />
  </AdminShell>
</template>
