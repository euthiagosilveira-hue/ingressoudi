<script setup lang="ts">
import { computed, ref } from 'vue'
import { BuildingStorefrontIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'

import StatusBadge from '~/components/StatusBadge.vue'
import { formatDataHora, formatNumero } from '~/utils/format'
import { ocupacao, situacaoEvento, type EventoPainel } from '~/utils/painelPlataforma'

const props = defineProps<{
  evento: EventoPainel
  abrindo?: boolean
}>()

const emit = defineEmits<{
  abrir: [evento: EventoPainel]
}>()

const imagemOk = ref(true)
const situacao = computed(() => situacaoEvento(props.evento))
const percentual = computed(() => ocupacao(props.evento.vendidos, props.evento.capacidade))
</script>

<template>
  <button
    type="button"
    :disabled="props.abrindo"
    :aria-label="`Abrir o dashboard de ${props.evento.nome} (${props.evento.organizacaoNome})`"
    class="group flex h-full w-full cursor-pointer flex-col overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900 text-left transition-colors duration-150 hover:border-amber-400/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 disabled:cursor-wait disabled:opacity-60"
    @click="emit('abrir', props.evento)"
  >
    <div class="relative aspect-[16/9] w-full overflow-hidden bg-zinc-950">
      <img
        v-if="props.evento.imagemUrl && imagemOk"
        :src="props.evento.imagemUrl"
        :alt="props.evento.nome"
        class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
        @error="imagemOk = false"
      />
      <div v-else class="flex h-full w-full items-center justify-center">
        <CalendarDaysIcon class="h-10 w-10 text-zinc-700" />
      </div>
      <StatusBadge class="absolute left-3 top-3" :status="situacao.tom" :label="situacao.rotulo" />
    </div>

    <div class="flex flex-1 flex-col gap-1 p-4">
      <p class="truncate font-semibold text-white group-hover:text-amber-400">{{ props.evento.nome }}</p>
      <p class="flex items-center gap-1.5 truncate text-xs text-amber-300/90">
        <BuildingStorefrontIcon class="h-3.5 w-3.5 shrink-0" />
        {{ props.evento.organizacaoNome }}
      </p>
      <p class="truncate text-xs text-zinc-500">{{ formatDataHora(props.evento.inicioEm) }} · {{ props.evento.local }}</p>

      <div class="mt-auto pt-3">
        <div class="flex items-baseline justify-between text-xs">
          <span class="text-zinc-400">
            <strong class="text-sm text-white">{{ formatNumero(props.evento.vendidos) }}</strong>
            / {{ formatNumero(props.evento.capacidade) }} vendidos
          </span>
          <span v-if="props.evento.utilizados > 0" class="text-green-400">
            {{ formatNumero(props.evento.utilizados) }} entraram
          </span>
        </div>
        <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-zinc-800">
          <div class="h-full rounded-full bg-amber-400" :style="{ width: `${percentual}%` }" />
        </div>
      </div>
    </div>
  </button>
</template>
