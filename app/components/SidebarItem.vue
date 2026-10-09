<script setup lang="ts">
import type { Component } from 'vue'

const props = withDefaults(
  defineProps<{
    to: string
    icon: Component
    label: string
    badge?: string | number
    active?: boolean
    size?: 'md' | 'lg'
  }>(),
  {
    badge: '',
    active: false,
    size: 'md'
  }
)

const sizeClasses: Record<string, string> = {
  md: 'gap-3 px-3 py-2.5 text-sm',
  lg: 'gap-3.5 px-4 py-3 text-sm'
}

const iconClasses: Record<string, string> = {
  md: 'h-5 w-5',
  lg: 'h-[22px] w-[22px]'
}

const badgeClasses: Record<string, string> = {
  md: 'px-2 py-0.5 text-xs',
  lg: 'px-2.5 py-0.5 text-xs'
}
</script>

<template>
  <NuxtLink
    :to="props.to"
    class="group flex cursor-pointer items-center rounded-lg transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/40"
    :class="[
      sizeClasses[props.size],
      active ? 'bg-amber-400/10 text-amber-400' : 'text-zinc-400 hover:bg-zinc-800 hover:text-zinc-100'
    ]"
  >
    <component :is="props.icon" :class="iconClasses[props.size]" />
    <span class="flex-1">{{ label }}</span>
    <span
      v-if="badge !== ''"
      class="rounded-full font-semibold"
      :class="[
        badgeClasses[props.size],
        active ? 'bg-amber-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300'
      ]"
    >
      {{ badge }}
    </span>
  </NuxtLink>
</template>
