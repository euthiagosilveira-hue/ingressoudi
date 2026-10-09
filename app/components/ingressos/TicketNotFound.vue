<script setup lang="ts">
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'

function voltar() {
  navigateTo('/ingressos')
}
</script>

<template>
  <div
    class="mx-auto flex max-w-xl flex-col items-center justify-center rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-16 text-center"
  >
    <p class="text-base font-semibold text-white">Ingresso não encontrado</p>
    <p class="mt-1 text-sm text-zinc-500">
      Não foi possível localizar o ingresso solicitado.
    </p>
    <AppButton variant="primary" class="mt-6" @click="voltar">
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para ingressos
    </AppButton>
  </div>
</template>
