<script setup lang="ts">
import { computed } from 'vue'

import type { CheckoutStep } from '~/types/checkout'

const props = withDefaults(
  defineProps<{
    step: CheckoutStep
    criando?: boolean
  }>(),
  { criando: false }
)

const emit = defineEmits<{
  voltar: []
  proximo: []
}>()

const voltarLabel = computed(() =>
  props.step === 'QUANTIDADE' ? 'Voltar para o evento' : 'Voltar'
)

const proximoLabel = computed(() => {
  if (props.step !== 'REVISAO') return 'Continuar'
  return props.criando ? 'Confirmando pedido...' : 'Confirmar pedido'
})

const secundario =
  'flex w-full items-center justify-center rounded-xl border border-zinc-700 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 sm:w-auto'

const primario =
  'flex w-full items-center justify-center rounded-xl bg-amber-400 px-8 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto'
</script>

<template>
  <div class="flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
    <button type="button" :class="secundario" @click="emit('voltar')">
      {{ voltarLabel }}
    </button>

    <button type="button" :class="primario" :disabled="props.criando" @click="emit('proximo')">
      {{ proximoLabel }}
    </button>
  </div>
</template>
