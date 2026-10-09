<script setup lang="ts">
import { computed } from 'vue'

import type { PaymentSlice } from '~/types/dashboard'

const props = defineProps<{
  data: PaymentSlice[]
}>()

const total = computed(() => props.data.reduce((sum, slice) => sum + slice.value, 0))

const slices = computed(() => {
  let acc = 0
  return props.data.map((slice) => {
    const start = acc
    const percent = total.value ? (slice.value / total.value) * 100 : 0
    acc += percent
    return { ...slice, start, end: acc, percent }
  })
})

const gradient = computed(() => {
  const stops = slices.value.map((slice) => `${slice.color} ${slice.start}% ${slice.end}%`)
  return `conic-gradient(${stops.join(', ')})`
})

function formatPercent(value: number) {
  return `${value.toFixed(1).replace('.', ',')}%`
}
</script>

<template>
  <BaseCard :padded="false" class="flex h-full flex-col p-5 sm:p-6">
    <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Status dos pagamentos
    </h3>

    <div class="mt-6 flex flex-1 items-center justify-center py-3">
      <div class="relative h-48 w-48 rounded-full" :style="{ background: gradient }">
        <div class="absolute inset-8 rounded-full bg-zinc-900"></div>
      </div>
    </div>

    <div class="mt-7 space-y-3.5 text-sm">
      <div
        v-for="slice in slices"
        :key="slice.key"
        class="flex items-center gap-2.5"
      >
        <span
          class="h-3 w-3 shrink-0 rounded-full"
          :style="{ backgroundColor: slice.color }"
        ></span>
        <span class="flex-1 text-zinc-300">{{ slice.label }}</span>
        <span class="w-10 text-right tabular-nums text-zinc-100">{{ slice.value }}</span>
        <span class="w-16 text-right tabular-nums text-zinc-500">({{ formatPercent(slice.percent) }})</span>
      </div>
    </div>
  </BaseCard>
</template>
