<script setup lang="ts">
import { ChevronRightIcon } from '@heroicons/vue/24/outline'

import type { ArtigoAjuda } from '~/utils/ajuda'
import { caminhoArtigoAjuda } from '~/utils/ajuda'

defineProps<{ artigo: ArtigoAjuda }>()
</script>

<template>
  <NuxtLink
    :to="caminhoArtigoAjuda(artigo.slug)"
    class="group flex items-center gap-3 rounded-xl border border-zinc-800 bg-zinc-900/70 px-4 py-3.5 transition-colors hover:border-amber-400/40 hover:bg-zinc-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
  >
    <div class="min-w-0 flex-1">
      <p class="font-semibold text-white group-hover:text-amber-300">{{ artigo.titulo }}</p>
      <p class="mt-0.5 text-sm text-zinc-400">{{ artigo.resumo }}</p>
    </div>
    <ChevronRightIcon class="h-5 w-5 shrink-0 text-zinc-600 group-hover:text-amber-400" />
  </NuxtLink>
</template>
