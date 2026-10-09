<script setup lang="ts">
import { computed } from 'vue'
import { CheckIcon } from '@heroicons/vue/24/outline'

import { formatDataNumerica, formatHora } from '~/utils/format'
import type { TicketListItem } from '~/types/ingresso'

const props = defineProps<{
  ingresso: TicketListItem
}>()

const foiUtilizado = computed(
  () => props.ingresso.status === 'UTILIZADO' && !!props.ingresso.utilizadoEm
)
</script>

<template>
  <div v-if="foiUtilizado" class="inline-flex items-center gap-2">
    <CheckIcon class="h-4 w-4 shrink-0 text-green-300" />
    <div class="leading-tight">
      <p class="text-sm text-zinc-200">{{ formatDataNumerica(props.ingresso.utilizadoEm ?? '') }}</p>
      <p class="text-xs text-zinc-500">{{ formatHora(props.ingresso.utilizadoEm ?? '') }}</p>
    </div>
  </div>
  <span v-else class="text-sm text-zinc-600">—</span>
</template>
