<script setup lang="ts">
import { computed } from 'vue'
import type { Component } from 'vue'
import { ClockIcon, FireIcon, HandRaisedIcon } from '@heroicons/vue/24/outline'

import type { LotActivationType } from '~/types/lote'
import { rotuloAtivacao } from '~/utils/lotes'

const props = defineProps<{
  tipo: LotActivationType
}>()

const icones: Record<LotActivationType, Component> = {
  MANUAL: HandRaisedIcon,
  ESGOTAMENTO: FireIcon,
  DATA_HORA: ClockIcon
}

const icone = computed(() => icones[props.tipo])
const rotulo = computed(() => rotuloAtivacao(props.tipo))
</script>

<template>
  <span class="inline-flex items-center gap-1.5 text-xs text-zinc-300">
    <component :is="icone" class="h-4 w-4 shrink-0 text-zinc-500" />
    {{ rotulo }}
  </span>
</template>
