<script setup lang="ts">
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  mensagem: string
}>()

const emit = defineEmits<{
  retry: []
}>()
</script>

<template>
  <section class="space-y-4 rounded-2xl border border-red-500/40 bg-red-500/5 p-6 text-center">
    <ExclamationTriangleIcon class="mx-auto h-8 w-8 text-amber-400" />
    <p class="text-base font-semibold text-zinc-200">{{ props.mensagem }}</p>
    <button
      type="button"
      class="inline-flex w-full items-center justify-center rounded-xl border border-amber-400/60 px-6 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click="emit('retry')"
    >
      Tentar novamente
    </button>

    <NuxtLink
      to="/recuperar-ingressos"
      class="block text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
    >
      Recuperar meus ingressos
    </NuxtLink>
  </section>
</template>
