<script setup lang="ts">
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  eventoSlug: string
  eventoNome: string
}>()
</script>

<template>
  <div class="space-y-3">
    <NuxtLink
      :to="`/eventos/${props.eventoSlug}`"
      class="inline-flex w-fit items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para o evento
    </NuxtLink>

    <div>
      <h1 class="text-2xl font-bold text-white sm:text-3xl">Pagamento</h1>
      <p class="mt-1 text-sm text-zinc-400">{{ props.eventoNome }}</p>
    </div>
  </div>
</template>
