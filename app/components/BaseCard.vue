<script setup lang="ts">
withDefaults(
  defineProps<{
    padded?: boolean
    id?: string
  }>(),
  { padded: true }
)
</script>

<template>
  <section
    :id="id"
    class="rounded-2xl border border-zinc-800 bg-zinc-900"
    :class="padded ? 'p-5' : ''"
  >
    <slot />
  </section>
</template>
