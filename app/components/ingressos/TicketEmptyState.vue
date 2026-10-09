<script setup lang="ts">
import { TicketIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'

const props = defineProps<{
  temFiltros: boolean
}>()

const emit = defineEmits<{
  limpar: []
}>()
</script>

<template>
  <div
    class="flex flex-col items-center justify-center rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-16 text-center"
  >
    <div
      class="flex h-14 w-14 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500"
    >
      <TicketIcon class="h-7 w-7" />
    </div>
    <p class="mt-4 text-base font-semibold text-white">Nenhum ingresso encontrado</p>
    <p class="mt-1 text-sm text-zinc-500">
      {{
        props.temFiltros
          ? 'Não encontramos ingressos com os filtros selecionados.'
          : 'Os ingressos aparecerão aqui quando os pedidos forem confirmados.'
      }}
    </p>
    <AppButton
      v-if="props.temFiltros"
      variant="primary"
      class="mt-6"
      @click="emit('limpar')"
    >
      Limpar filtros
    </AppButton>
  </div>
</template>
