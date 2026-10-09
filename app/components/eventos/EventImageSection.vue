<script setup lang="ts">
import { PhotoIcon } from '@heroicons/vue/24/outline'

import BaseCard from '~/components/BaseCard.vue'
import EventImageUploader from '~/components/eventos/EventImageUploader.vue'
import type { EventFormValue } from '~/types/evento'

const props = defineProps<{
  value: EventFormValue
}>()
</script>

<template>
  <BaseCard class="space-y-5">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      2. Imagem do evento
    </h2>

    <div class="grid grid-cols-1 gap-5 lg:grid-cols-2">
      <div
        class="relative aspect-video w-full overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950"
      >
        <img
          v-if="props.value.imagemUrl"
          :src="props.value.imagemUrl"
          alt="Pré-visualização da imagem do evento"
          class="h-full w-full object-cover"
        />
        <div
          v-else
          class="flex h-full w-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-zinc-800 via-zinc-900 to-black px-4 text-center"
        >
          <PhotoIcon class="h-8 w-8 text-amber-400/80" />
          <span class="text-sm text-zinc-400">Imagem do evento</span>
          <span class="text-xs text-zinc-600">Proporção 16:9</span>
        </div>
      </div>

      <EventImageUploader
        :model-value="props.value.imagemUrl"
        @update:model-value="(url) => (props.value.imagemUrl = url)"
      />
    </div>
  </BaseCard>
</template>
