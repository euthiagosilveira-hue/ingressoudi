<script setup lang="ts">
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'

withDefaults(
  defineProps<{
    title?: string
    subtitle?: string
  }>(),
  {
    title: 'Nenhum evento encontrado',
    subtitle: 'Tente ajustar os filtros ou crie um novo evento.'
  }
)

const emit = defineEmits<{
  create: []
}>()
</script>

<template>
  <div
    class="flex flex-col items-center justify-center rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-16 text-center"
  >
    <div
      class="flex h-14 w-14 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500"
    >
      <CalendarDaysIcon class="h-7 w-7" />
    </div>
    <p class="mt-4 text-base font-semibold text-white">{{ title }}</p>
    <p class="mt-1 text-sm text-zinc-500">{{ subtitle }}</p>
    <AppButton variant="primary" class="mt-6" @click="emit('create')">
      Criar evento
    </AppButton>
  </div>
</template>
