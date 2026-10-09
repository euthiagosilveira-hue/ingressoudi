<script setup lang="ts">
import { computed } from 'vue'
import type { Component } from 'vue'
import { QrCodeIcon, UserIcon } from '@heroicons/vue/24/outline'

import type { EntryMethod } from '~/types/entrada'

const props = defineProps<{
  metodo: EntryMethod
}>()

const mapa: Record<EntryMethod, { label: string; icone: Component; classes: string }> = {
  QR_CODE: {
    label: 'QR Code',
    icone: QrCodeIcon,
    classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300'
  },
  NOME: {
    label: 'Nome',
    icone: UserIcon,
    classes: 'border-zinc-700 bg-zinc-800/70 text-zinc-300'
  }
}

const info = computed(() => mapa[props.metodo])
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    <component :is="info.icone" class="h-3.5 w-3.5" />
    {{ info.label }}
  </span>
</template>
