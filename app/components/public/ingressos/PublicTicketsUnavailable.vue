<script setup lang="ts">
import { TicketIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  titulo: string
  descricao: string
  eventoSlug?: string
  checkoutToken?: string | null
}>()
</script>

<template>
  <section class="space-y-4 rounded-2xl border-2 border-zinc-700 bg-zinc-900 p-6 text-center">
    <div class="flex justify-center">
      <TicketIcon class="h-8 w-8 text-amber-400" />
    </div>
    <p class="text-lg font-bold uppercase tracking-wide text-zinc-200">{{ props.titulo }}</p>
    <p class="text-sm text-zinc-400">{{ props.descricao }}</p>

    <NuxtLink
      v-if="props.eventoSlug && props.checkoutToken"
      :to="`/eventos/${props.eventoSlug}/comprar/pagamento?token=${props.checkoutToken}`"
      class="mt-2 inline-flex w-full items-center justify-center rounded-xl border border-amber-400/60 px-6 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      Voltar ao pagamento
    </NuxtLink>

    <NuxtLink
      v-else-if="props.eventoSlug"
      :to="`/eventos/${props.eventoSlug}`"
      class="mt-2 inline-flex w-full items-center justify-center rounded-xl border border-zinc-700 px-6 py-3 text-sm font-bold uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white"
    >
      Voltar ao evento
    </NuxtLink>
  </section>
</template>
