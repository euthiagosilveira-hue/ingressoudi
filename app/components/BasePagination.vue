<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeftIcon, ChevronRightIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  pagina: number
  totalPaginas: number
}>()

const emit = defineEmits<{
  ir: [pagina: number]
}>()

const paginas = computed<Array<number | '...'>>(() => {
  const total = props.totalPaginas
  const atual = props.pagina

  if (total <= 7) {
    return Array.from({ length: total }, (_, indice) => indice + 1)
  }

  const itens: Array<number | '...'> = [1]
  const inicio = Math.max(2, atual - 1)
  const fim = Math.min(total - 1, atual + 1)

  if (inicio > 2) itens.push('...')
  for (let numero = inicio; numero <= fim; numero += 1) itens.push(numero)
  if (fim < total - 1) itens.push('...')
  itens.push(total)

  return itens
})

const base =
  'flex h-9 min-w-9 cursor-pointer items-center justify-center rounded-lg border px-3 text-sm font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 disabled:cursor-not-allowed disabled:opacity-40'
</script>

<template>
  <nav class="flex items-center justify-center gap-1.5" aria-label="Paginação">
    <button
      type="button"
      aria-label="Página anterior"
      :disabled="props.pagina <= 1"
      :class="[base, 'border-zinc-700 text-zinc-300 hover:border-zinc-600 hover:text-white']"
      @click="emit('ir', props.pagina - 1)"
    >
      <ChevronLeftIcon class="h-4 w-4" />
    </button>

    <template v-for="(item, indice) in paginas" :key="`${item}-${indice}`">
      <span v-if="item === '...'" class="px-1.5 text-sm text-zinc-600">…</span>
      <button
        v-else
        type="button"
        :aria-current="item === props.pagina ? 'page' : undefined"
        :class="[
          base,
          item === props.pagina
            ? 'border-amber-400/60 bg-amber-400/10 text-amber-300'
            : 'border-zinc-700 text-zinc-300 hover:border-zinc-600 hover:text-white'
        ]"
        @click="emit('ir', item)"
      >
        {{ item }}
      </button>
    </template>

    <button
      type="button"
      aria-label="Próxima página"
      :disabled="props.pagina >= props.totalPaginas"
      :class="[base, 'border-zinc-700 text-zinc-300 hover:border-zinc-600 hover:text-white']"
      @click="emit('ir', props.pagina + 1)"
    >
      <ChevronRightIcon class="h-4 w-4" />
    </button>
  </nav>
</template>
