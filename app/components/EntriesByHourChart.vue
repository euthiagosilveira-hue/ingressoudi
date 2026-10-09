<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/24/outline'

import type { EntryByHour } from '~/types/dashboard'

const props = defineProps<{
  data: EntryByHour[]
}>()

const width = 760
const height = 360
const padding = { top: 48, right: 44, bottom: 54, left: 50 }
const innerWidth = width - padding.left - padding.right
const innerHeight = height - padding.top - padding.bottom
const baseline = padding.top + innerHeight

const maxValue = computed(() => {
  const max = Math.max(...props.data.map((point) => point.entradas), 1)
  return Math.ceil(max / 10) * 10
})

const points = computed(() =>
  props.data.map((point, index) => {
    const x =
      props.data.length === 1
        ? padding.left + innerWidth / 2
        : padding.left + (innerWidth * index) / (props.data.length - 1)
    const y = padding.top + innerHeight * (1 - point.entradas / maxValue.value)
    return { ...point, x, y }
  })
)

const linePath = computed(() =>
  points.value.map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x},${point.y}`).join(' ')
)

const areaPath = computed(() => {
  if (points.value.length === 0) return ''
  const first = points.value[0]
  const last = points.value[points.value.length - 1]
  if (!first || !last) return ''
  return `${linePath.value} L${last.x},${baseline} L${first.x},${baseline} Z`
})

const gridLines = computed(() =>
  Array.from({ length: 5 }, (_, index) => {
    const y = padding.top + (innerHeight * index) / 4
    const value = Math.round(maxValue.value * (1 - index / 4))
    return { y, value }
  })
)
</script>

<template>
  <BaseCard :padded="false" class="flex h-full flex-col p-5 sm:p-6">
    <div class="flex items-center justify-between gap-3">
      <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
        Entradas por hora
      </h3>
      <button
        type="button"
        class="flex cursor-pointer items-center gap-2 rounded-lg border border-zinc-700 bg-zinc-900 px-3.5 py-2 text-sm text-zinc-300 transition-colors duration-150 hover:border-zinc-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        Hoje
        <ChevronDownIcon class="h-4 w-4 text-zinc-500" />
      </button>
    </div>

    <div class="mt-5 flex-1 overflow-x-auto">
      <svg
        :viewBox="`0 0 ${width} ${height}`"
        class="h-auto w-full min-w-[600px]"
        role="img"
        aria-label="Gráfico de entradas por hora"
      >
        <defs>
          <linearGradient id="entriesAreaGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#fbbf24" stop-opacity="0.32" />
            <stop offset="100%" stop-color="#fbbf24" stop-opacity="0" />
          </linearGradient>
        </defs>

        <g v-for="line in gridLines" :key="line.y">
          <line
            :x1="padding.left"
            :y1="line.y"
            :x2="width - padding.right"
            :y2="line.y"
            stroke="#27272a"
            stroke-width="1"
          />
          <text
            :x="padding.left - 12"
            :y="line.y + 4"
            text-anchor="end"
            font-size="12"
            fill="#52525b"
          >
            {{ line.value }}
          </text>
        </g>

        <path :d="areaPath" fill="url(#entriesAreaGrad)" />

        <path
          :d="linePath"
          fill="none"
          stroke="#fbbf24"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
        />

        <g v-for="point in points" :key="point.hora">
          <text
            :x="point.x"
            :y="point.y - 14"
            text-anchor="middle"
            font-size="12"
            font-weight="600"
            fill="#f4f4f5"
          >
            {{ point.entradas }}
          </text>
          <circle
            :cx="point.x"
            :cy="point.y"
            r="4.5"
            fill="#fbbf24"
            stroke="#09090b"
            stroke-width="2"
          />
          <text
            :x="point.x"
            :y="height - 16"
            text-anchor="middle"
            font-size="13"
            fill="#71717a"
          >
            {{ point.hora }}
          </text>
        </g>
      </svg>
    </div>
  </BaseCard>
</template>
