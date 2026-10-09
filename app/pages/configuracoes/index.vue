<script setup lang="ts">
import { UsersIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import PageHeader from '~/components/PageHeader.vue'

definePageMeta({
  title: 'Configurações',
  description: 'Gerencie as configurações do sistema.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth']
})
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Configurações" subtitle="Gerencie as configurações do sistema." />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <NuxtLink to="/configuracoes/usuarios" class="group">
        <BaseCard class="h-full transition-colors duration-200 group-hover:border-amber-400/40">
          <div class="flex items-start gap-3">
            <span
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400"
            >
              <UsersIcon class="h-6 w-6" />
            </span>
            <div>
              <p class="text-sm font-semibold text-white transition-colors group-hover:text-amber-400">
                Usuários
              </p>
              <p class="mt-1 text-xs text-zinc-500">
                Gerencie quem pode acessar o administrativo e a portaria.
              </p>
            </div>
          </div>
        </BaseCard>
      </NuxtLink>
    </div>
  </div>
</template>
