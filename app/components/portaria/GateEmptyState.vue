<script setup lang="ts">
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
</script>

<template>
  <BaseCard class="flex flex-col items-center justify-center px-6 py-16 text-center">
    <div
      class="flex h-14 w-14 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500"
    >
      <CalendarDaysIcon class="h-7 w-7" />
    </div>
    <p class="mt-4 text-base font-semibold text-white">Selecione um evento</p>
    <p class="mt-1 text-sm text-zinc-500">
      Escolha o evento em operação para começar a validar ingressos.
    </p>
  </BaseCard>
</template>
