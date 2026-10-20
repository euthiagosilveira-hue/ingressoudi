<script setup lang="ts">
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

import AdminDashboard from '~/components/AdminDashboard.vue'

definePageMeta({
  title: 'Dashboard do evento',
  description: 'Vendas, entradas e pagamentos deste evento.',
  layout: 'dashboard-test-layout',
  sidebarActive: 'Eventos',
  middleware: ['admin-auth']
})

const route = useRoute()
const eventoId = String(route.params.id)
</script>

<template>
  <div class="space-y-6">
    <NuxtLink
      to="/eventos"
      class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para eventos
    </NuxtLink>

    <AdminDashboard :evento-id="eventoId" />
  </div>
</template>
