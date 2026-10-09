<script setup lang="ts">
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  titulo: string
  descricao: string
  eventoSlug?: string
  tom?: 'neutro' | 'alerta'
}>()

const tomClasses = props.tom === 'alerta'
  ? 'border-red-500/40 bg-red-500/5'
  : 'border-zinc-700 bg-zinc-900'
</script>

<template>
  <section class="space-y-4 rounded-2xl border-2 p-5 text-center sm:p-6" :class="tomClasses">
    <div class="flex justify-center">
      <ExclamationTriangleIcon class="h-8 w-8 text-amber-400" />
    </div>
    <p class="text-lg font-bold uppercase tracking-wide text-zinc-200">{{ props.titulo }}</p>
    <p class="text-sm text-zinc-400">{{ props.descricao }}</p>

    <NuxtLink
      v-if="props.eventoSlug"
      :to="`/eventos/${props.eventoSlug}`"
      class="mt-2 inline-flex w-full items-center justify-center rounded-xl border border-amber-400/60 px-6 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      Voltar ao evento
    </NuxtLink>
  </section>
</template>
