<script setup lang="ts">
import { PlayIcon } from '@heroicons/vue/24/solid'

import { urlEmbedYoutube } from '~/utils/videoApresentacao'

const props = defineProps<{ videoId: string }>()

// O player do YouTube so e carregado quando o visitante clica: a pagina abre
// leve, sem cookies e sem som tocando sozinho.
const tocando = ref(false)
</script>

<template>
  <div
    class="relative aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950 shadow-[0_0_60px_rgba(217,177,56,0.12)]"
  >
    <iframe
      v-if="tocando"
      :src="urlEmbedYoutube(props.videoId)"
      title="Vídeo de apresentação do Ingressoudi"
      class="absolute inset-0 h-full w-full"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      referrerpolicy="strict-origin-when-cross-origin"
      allowfullscreen
    />
    <button
      v-else
      type="button"
      class="group absolute inset-0 h-full w-full"
      aria-label="Assistir ao vídeo de apresentação"
      @click="tocando = true"
    >
      <img
        src="/video-apresentacao-capa.webp"
        alt=""
        width="1280"
        height="720"
        loading="lazy"
        decoding="async"
        class="h-full w-full object-cover opacity-80 transition-opacity group-hover:opacity-100"
      >
      <span class="absolute inset-0 flex items-center justify-center">
        <span
          class="flex h-16 w-16 items-center justify-center rounded-full bg-amber-400 text-zinc-950 shadow-lg transition-transform group-hover:scale-110 sm:h-20 sm:w-20"
        >
          <PlayIcon class="ml-1 h-8 w-8 sm:h-10 sm:w-10" />
        </span>
      </span>
      <span
        class="absolute bottom-3 left-3 rounded-lg bg-zinc-950/80 px-3 py-1 text-xs font-semibold text-zinc-200 sm:bottom-4 sm:left-4 sm:text-sm"
      >
        Veja como funciona · 1 min
      </span>
    </button>
  </div>
</template>
