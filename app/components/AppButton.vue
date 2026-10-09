<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'outline' | 'outlineAccent' | 'ghost' | 'danger'
    size?: 'sm' | 'md' | 'lg'
    block?: boolean
    disabled?: boolean
    type?: 'button' | 'submit'
    to?: string
  }>(),
  {
    variant: 'outline',
    size: 'md',
    block: false,
    disabled: false,
    type: 'button',
    to: ''
  }
)

const variantClasses: Record<string, string> = {
  primary: 'bg-amber-400 text-zinc-950 hover:bg-amber-300',
  outline: 'border border-amber-400/60 text-amber-400 hover:bg-amber-400/10',
  outlineAccent: 'border border-amber-400/60 text-amber-400 hover:bg-amber-400 hover:text-zinc-950',
  ghost: 'bg-zinc-800 text-zinc-200 hover:bg-zinc-700',
  danger: 'bg-red-500/90 text-white hover:bg-red-500'
}

const sizeClasses: Record<string, string> = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2.5 text-xs',
  lg: 'px-6 py-3 text-sm'
}

const classes = computed(() => [
  'inline-flex cursor-pointer items-center justify-center gap-2 rounded-lg font-semibold uppercase tracking-wide transition-colors duration-150',
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50',
  variantClasses[props.variant],
  sizeClasses[props.size],
  props.block ? 'w-full' : '',
  props.disabled ? 'pointer-events-none opacity-50' : ''
])
</script>

<template>
  <NuxtLink v-if="to" :to="to" :class="classes">
    <slot />
  </NuxtLink>
  <button v-else :type="type" :disabled="disabled" :class="classes">
    <slot />
  </button>
</template>
