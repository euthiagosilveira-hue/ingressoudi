<script setup lang="ts">
import type { Component } from 'vue'

const props = withDefaults(
  defineProps<{
    icon: Component
    label: string
    value: string
    subtitle?: string
    iconClass?: string
    circleClass?: string
    valueClass?: string
    subtitleClass?: string
  }>(),
  {
    subtitle: '',
    iconClass: 'text-amber-400',
    circleClass: 'border-amber-400/60',
    valueClass: 'text-white',
    subtitleClass: 'text-zinc-400'
  }
)
</script>

<template>
  <BaseCard :padded="false" class="flex h-full items-center gap-5 p-5 sm:p-6">
    <div
      class="flex h-[56px] w-[56px] shrink-0 items-center justify-center rounded-full border bg-zinc-950"
      :class="props.circleClass"
    >
      <component :is="props.icon" class="h-6 w-6 leading-none" :class="props.iconClass" />
    </div>
    <div class="flex min-w-0 flex-col justify-center">
      <p class="text-[11px] uppercase tracking-wide text-zinc-400">{{ label }}</p>
      <p
        class="mt-1 truncate text-[22px] font-bold leading-tight"
        :class="props.valueClass"
      >
        {{ value }}
      </p>
      <p v-if="subtitle" class="mt-0.5 truncate text-xs" :class="props.subtitleClass">
        {{ subtitle }}
      </p>
    </div>
  </BaseCard>
</template>
