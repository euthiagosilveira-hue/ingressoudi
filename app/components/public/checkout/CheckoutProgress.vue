<script setup lang="ts">
import { computed } from 'vue'

import type { CheckoutStep } from '~/types/checkout'

const props = defineProps<{
  step: CheckoutStep
}>()

const passos = [
  { key: 'QUANTIDADE', label: 'Quantidade' },
  { key: 'PARTICIPANTES', label: 'Participantes' },
  { key: 'COMPRADOR', label: 'Comprador' },
  { key: 'REVISAO', label: 'Revisão' }
] as const

const indiceAtual = computed(() => {
  if (props.step === 'RESERVA_CRIADA') return passos.length
  return passos.findIndex((passo) => passo.key === props.step)
})

const rotuloMobile = computed(() => {
  if (props.step === 'RESERVA_CRIADA') return 'Reserva criada'
  const passo = passos[indiceAtual.value]
  return passo ? passo.label : 'Revisão'
})
</script>

<template>
  <div>
    <!-- Desktop: passos horizontais -->
    <ol class="hidden items-center gap-3 sm:flex">
      <li
        v-for="(passo, indice) in passos"
        :key="passo.key"
        class="flex items-center gap-2"
      >
        <span
          class="flex h-8 w-8 items-center justify-center rounded-full border text-sm font-bold"
          :class="
            indice < indiceAtual
              ? 'border-amber-400/60 bg-amber-400/10 text-amber-300'
              : indice === indiceAtual
                ? 'border-amber-400 bg-amber-400 text-zinc-950'
                : 'border-zinc-700 text-zinc-500'
          "
        >
          {{ indice + 1 }}
        </span>
        <span
          class="text-sm"
          :class="indice <= indiceAtual ? 'text-zinc-200' : 'text-zinc-500'"
        >
          {{ passo.label }}
        </span>
        <span
          v-if="indice < passos.length - 1"
          class="mx-1 h-px w-8 bg-zinc-800"
          aria-hidden="true"
        ></span>
      </li>
    </ol>

    <!-- Mobile: compacto -->
    <p class="text-sm text-zinc-400 sm:hidden">
      <span class="font-semibold text-zinc-200">
        Etapa {{ Math.min(indiceAtual + 1, passos.length) }} de {{ passos.length }}
      </span>
      — {{ rotuloMobile }}
    </p>
  </div>
</template>
