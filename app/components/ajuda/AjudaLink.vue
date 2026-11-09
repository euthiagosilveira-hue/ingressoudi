<script setup lang="ts">
import { QuestionMarkCircleIcon } from '@heroicons/vue/24/outline'

import { caminhoArtigoAjuda, obterArtigoAjuda } from '~/utils/ajuda'

const props = defineProps<{ artigo: string }>()

// Abre em outra aba para nao perder o que esta sendo preenchido.
const titulo = obterArtigoAjuda(props.artigo)?.titulo ?? 'Central de ajuda'
</script>

<template>
  <a
    :href="caminhoArtigoAjuda(props.artigo)"
    target="_blank"
    rel="noopener"
    :title="`Ajuda: ${titulo}`"
    :aria-label="`Ajuda: ${titulo} (abre em outra aba)`"
    class="inline-flex items-center gap-1.5 rounded-lg border border-zinc-700 px-2.5 py-1.5 text-xs font-semibold uppercase tracking-wide text-zinc-300 transition-colors hover:border-amber-400/50 hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
  >
    <QuestionMarkCircleIcon class="h-4 w-4" />
    Ajuda
  </a>
</template>
