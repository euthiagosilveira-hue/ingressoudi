<script setup lang="ts">
import { MagnifyingGlassIcon, QrCodeIcon } from '@heroicons/vue/24/outline'

import type { GateMode } from '~/types/portaria'

const props = defineProps<{
  modelValue: GateMode
}>()

const emit = defineEmits<{
  'update:modelValue': [value: GateMode]
}>()

const base =
  'flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl border px-4 py-4 text-sm font-semibold uppercase tracking-wide transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50'
</script>

<template>
  <div class="grid grid-cols-2 gap-3" role="tablist" aria-label="Modo de leitura">
    <button
      type="button"
      role="tab"
      :aria-selected="props.modelValue === 'QR'"
      :class="[
        base,
        props.modelValue === 'QR'
          ? 'border-amber-400/60 bg-amber-400/10 text-amber-300'
          : 'border-zinc-700 text-zinc-300 hover:border-zinc-600 hover:text-white'
      ]"
      @click="emit('update:modelValue', 'QR')"
    >
      <QrCodeIcon class="h-5 w-5" />
      QR Code
    </button>

    <button
      type="button"
      role="tab"
      :aria-selected="props.modelValue === 'NOME'"
      :class="[
        base,
        props.modelValue === 'NOME'
          ? 'border-amber-400/60 bg-amber-400/10 text-amber-300'
          : 'border-zinc-700 text-zinc-300 hover:border-zinc-600 hover:text-white'
      ]"
      @click="emit('update:modelValue', 'NOME')"
    >
      <MagnifyingGlassIcon class="h-5 w-5" />
      Buscar por nome
    </button>
  </div>
</template>
