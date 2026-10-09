<script setup lang="ts">
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'
</script>

<template>
  <section class="mx-auto flex max-w-2xl flex-col items-center px-4 py-20 text-center sm:py-28">
    <div
      class="flex h-16 w-16 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500"
    >
      <CalendarDaysIcon class="h-8 w-8" />
    </div>
    <h1 class="mt-6 text-2xl font-bold text-white">Evento não encontrado</h1>
    <p class="mt-2 text-sm text-zinc-400">Não foi possível localizar este evento.</p>
    <NuxtLink
      to="/eventos-publicos"
      class="mt-8 inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-8 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      Ver eventos
    </NuxtLink>
  </section>
</template>
