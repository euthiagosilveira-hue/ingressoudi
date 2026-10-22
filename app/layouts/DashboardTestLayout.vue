<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from '#imports'

import AdminShell from '~/components/AdminShell.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { iniciais } from '~/utils/marca'

const route = useRoute()
const title = computed(() => String(route.meta.title ?? 'Dashboard'))
const subtitulo = computed(() => String(route.meta.description ?? ''))

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
            <p v-if="subtitulo" class="mt-2 text-base text-zinc-400">{{ subtitulo }}</p>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <div
              class="flex h-14 items-center gap-3 rounded-xl border border-zinc-700 bg-zinc-900 p-1.5 pr-4"
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
            </div>
          </div>
        </div>
      </div>
    </template>

    <slot />
  </AdminShell>
</template>
