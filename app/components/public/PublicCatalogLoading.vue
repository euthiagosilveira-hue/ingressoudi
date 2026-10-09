<template>
  <div class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 sm:py-12" role="status" aria-live="polite">
    <div class="h-7 w-40 animate-pulse rounded bg-zinc-800"></div>
    <div class="mt-3 h-4 w-64 animate-pulse rounded bg-zinc-800"></div>

    <div class="mt-8 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="indice in 3"
        :key="indice"
        class="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900"
      >
        <div class="aspect-video w-full animate-pulse bg-zinc-800"></div>
        <div class="space-y-3 p-4">
          <div class="h-4 w-3/4 animate-pulse rounded bg-zinc-800"></div>
          <div class="h-3 w-1/2 animate-pulse rounded bg-zinc-800"></div>
          <div class="h-3 w-2/3 animate-pulse rounded bg-zinc-800"></div>
        </div>
      </div>
    </div>

    <span class="sr-only">Carregando eventos…</span>
  </div>
</template>
