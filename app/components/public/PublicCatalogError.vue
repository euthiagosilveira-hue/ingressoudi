<script setup lang="ts">
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

withDefaults(
  defineProps<{
    mensagem?: string
  }>(),
  { mensagem: 'Não foi possível carregar os eventos agora.' }
)

const emit = defineEmits<{
  retry: []
}>()
</script>

<template>
  <section class="mx-auto flex max-w-xl flex-col items-center px-4 py-20 text-center">
    <div
      class="flex h-14 w-14 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-amber-400"
    >
      <ExclamationTriangleIcon class="h-7 w-7" />
    </div>
    <p class="mt-4 text-base font-semibold text-white">{{ mensagem }}</p>
    <button
      type="button"
      class="mt-6 inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-8 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click="emit('retry')"
    >
      Tentar novamente
    </button>
  </section>
</template>
