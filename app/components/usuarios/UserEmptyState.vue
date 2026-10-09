<script setup lang="ts">
import { UsersIcon } from '@heroicons/vue/24/outline'

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
    <span
      class="flex h-14 w-14 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500"
    >
      <UsersIcon class="h-7 w-7" />
    </span>
    <p class="mt-4 text-base font-semibold text-white">Nenhum usuário encontrado</p>
    <p class="mt-1 text-sm text-zinc-500">
      {{
        props.temFiltros
          ? 'Não encontramos usuários com os termos buscados.'
          : 'Os usuários aparecerão aqui após o primeiro convite.'
      }}
    </p>
    <AppButton v-if="props.temFiltros" variant="primary" class="mt-6" @click="emit('limpar')">
      Limpar busca
    </AppButton>
  </div>
</template>
