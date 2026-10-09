<script setup lang="ts">
import { onMounted, ref } from 'vue'

import TicketDetails from '~/components/ingressos/TicketDetails.vue'
import TicketNotFound from '~/components/ingressos/TicketNotFound.vue'
import { obterIngressoAdmin } from '~/services/admin/ingressos'
import type { TicketDetail } from '~/types/ingresso'
import { mapearIngressoAdminParaDetalhe } from '~/utils/ingressos'

definePageMeta({
  title: 'Detalhe do ingresso',
  description: 'Consulte os dados do ingresso.',
  layout: 'admin-layout',
  sidebarActive: 'Ingressos',
  middleware: ['admin-auth']
})

const route = useRoute()
const ingresso = ref<TicketDetail | null>(null)
const carregado = ref(false)

onMounted(async () => {
  try {
    const row = await obterIngressoAdmin(String(route.params.id))
    ingresso.value = row ? mapearIngressoAdminParaDetalhe(row) : null
  } catch {
    ingresso.value = null
  } finally {
    carregado.value = true
  }
})
</script>

<template>
  <TicketDetails v-if="ingresso" :ingresso="ingresso" />
  <TicketNotFound v-else-if="carregado" />
</template>
