<script setup lang="ts">
import { computed } from 'vue'
import { MagnifyingGlassIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  modelValue: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const busca = computed({
  get: () => props.modelValue,
  set: (valor: string) => emit('update:modelValue', valor)
})
</script>

<template>
  <BaseCard :padded="false" class="p-4">
    <div class="relative w-full sm:max-w-sm">
      <MagnifyingGlassIcon
        class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-zinc-500"
      />
      <input
        v-model="busca"
        type="search"
        placeholder="Buscar por nome ou e-mail..."
        class="w-full rounded-lg border border-zinc-700 bg-zinc-950 py-2.5 pl-9 pr-3.5 text-sm text-white placeholder-zinc-500 transition-colors focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
      />
    </div>
  </BaseCard>
</template>
