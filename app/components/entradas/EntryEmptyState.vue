<script setup lang="ts">
import { ArrowRightOnRectangleIcon } from '@heroicons/vue/24/outline'

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
      <ArrowRightOnRectangleIcon class="h-7 w-7" />
    </div>
    <p class="mt-4 text-base font-semibold text-white">Nenhuma entrada encontrada</p>
    <p class="mt-1 text-sm text-zinc-500">
      {{
        props.temFiltros
          ? 'Não encontramos entradas com os filtros selecionados.'
          : 'As entradas registradas pela Portaria aparecerão aqui.'
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
