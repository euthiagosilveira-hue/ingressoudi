<script setup lang="ts">
import { computed } from 'vue'

import type { VipStatus } from '~/types/vip'
import { rotuloStatusVip } from '~/utils/vip'

const props = defineProps<{
  status: VipStatus
}>()

const rotulo = computed(() => rotuloStatusVip(props.status))
const classes = computed(() =>
  props.status === 'ENTROU'
    ? 'border-green-500/40 bg-green-500/10 text-green-300'
    : 'border-amber-400/40 bg-amber-400/10 text-amber-300'
)
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="classes"
  >
    {{ rotulo }}
  </span>
</template>
