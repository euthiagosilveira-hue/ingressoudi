<script setup lang="ts">
import { computed } from 'vue'
import { BanknotesIcon, GlobeAltIcon, UsersIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import PageHeader from '~/components/PageHeader.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'

definePageMeta({
  title: 'Configurações',
  description: 'Gerencie as configurações do sistema.',
  layout: 'admin-layout',
  sidebarActive: 'Configurações',
  middleware: ['admin-auth']
})

const { operador } = useOperatorAuth()
// No modo suporte, Mercado Pago e Usuarios sao do produtor e ficam bloqueados.
const modoSuporte = computed(() => Boolean(operador.value?.modoSuporte))
const linkPublico = computed(() => {
  const slug = operador.value?.organizacao?.slug
  return slug ? `/${slug}` : null
})
</script>

<template>
  <div class="space-y-6">
    <PageHeader title="Configurações" subtitle="Gerencie as configurações do sistema." />

    <p
      v-if="modoSuporte"
      role="status"
      class="rounded-xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-100"
    >
      No modo suporte, a conta do Mercado Pago e os usuários da equipe ficam bloqueados: são do produtor.
    </p>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
      <NuxtLink v-if="!modoSuporte" to="/configuracoes/usuarios" class="group">
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

      <NuxtLink to="/configuracoes/pagina-publica" class="group">
        <BaseCard class="h-full transition-colors duration-200 group-hover:border-amber-400/40">
          <div class="flex items-start gap-3">
            <span
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400"
            >
              <GlobeAltIcon class="h-6 w-6" />
            </span>
            <div class="min-w-0">
              <p class="text-sm font-semibold text-white transition-colors group-hover:text-amber-400">
                Sua página de eventos
              </p>
              <p v-if="linkPublico" class="mt-1 truncate text-xs text-zinc-500">{{ linkPublico }}</p>
              <p class="mt-1 text-xs text-zinc-500">Link para divulgar, logo e cor da sua casa.</p>
            </div>
          </div>
        </BaseCard>
      </NuxtLink>

      <NuxtLink v-if="!modoSuporte" to="/configuracoes/mercado-pago" class="group">
        <BaseCard class="h-full transition-colors duration-200 group-hover:border-amber-400/40">
          <div class="flex items-start gap-3">
            <span
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400"
            >
              <BanknotesIcon class="h-6 w-6" />
            </span>
            <div>
              <p class="text-sm font-semibold text-white transition-colors group-hover:text-amber-400">
                Mercado Pago
              </p>
              <p class="mt-1 text-xs text-zinc-500">
                Conecte a conta que recebe as vendas Pix e veja a taxa de serviço.
              </p>
            </div>
          </div>
        </BaseCard>
      </NuxtLink>
    </div>
  </div>
</template>
