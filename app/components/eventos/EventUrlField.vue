<script setup lang="ts">
import { computed } from 'vue'
import { PencilSquareIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  modelValue: string
  manual: boolean
  error?: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
  'edit-manual': []
  'use-auto': []
}>()

const urlExibida = computed(() => `/eventos/${props.modelValue || ''}`)

function aoDigitar(evento: Event) {
  emit('update:modelValue', (evento.target as HTMLInputElement).value)
}
</script>

<template>
  <div>
    <span class="mb-1.5 block text-sm font-medium text-zinc-300">URL do evento</span>

    <template v-if="!props.manual">
      <div class="flex flex-wrap items-center gap-2">
        <code
          class="min-w-0 flex-1 truncate rounded-lg border border-zinc-700 bg-zinc-950 px-3.5 py-2.5 text-sm text-zinc-300"
        >
          {{ urlExibida }}
        </code>
        <button
          type="button"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-zinc-700 px-3 py-2 text-xs font-medium text-zinc-300 transition-colors hover:border-amber-400/60 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
          @click="emit('edit-manual')"
        >
          <PencilSquareIcon class="h-4 w-4" />
          Editar URL
        </button>
      </div>
      <p v-if="props.error" class="mt-1.5 text-xs text-red-400">{{ props.error }}</p>
      <p v-else class="mt-1.5 text-xs text-zinc-500">
        Gerada automaticamente a partir do nome do evento.
      </p>
    </template>

    <template v-else>
      <label class="block">
        <span class="mb-1.5 block text-xs font-medium text-zinc-400">URL personalizada</span>
        <div
          class="flex items-center rounded-lg border bg-zinc-900 transition-colors focus-within:ring-2"
          :class="
            props.error
              ? 'border-red-500/60 focus-within:border-red-500 focus-within:ring-red-500/30'
              : 'border-zinc-700 focus-within:border-amber-400/60 focus-within:ring-amber-400/30'
          "
        >
          <span class="shrink-0 pl-3.5 text-sm text-zinc-500">/eventos/</span>
          <input
            :value="props.modelValue"
            type="text"
            placeholder="banda-conexao"
            class="min-w-0 flex-1 bg-transparent px-1 py-2.5 pr-3.5 text-sm text-white placeholder-zinc-500 focus:outline-none"
            @input="aoDigitar"
          >
        </div>
      </label>

      <div class="mt-1.5 flex flex-wrap items-center justify-between gap-2">
        <p v-if="props.error" class="text-xs text-red-400">{{ props.error }}</p>
        <p v-else class="text-xs text-zinc-500">Use letras minúsculas, números e hífens.</p>
        <button
          type="button"
          class="text-xs font-medium text-amber-400 transition-colors hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
          @click="emit('use-auto')"
        >
          Usar URL automática
        </button>
      </div>
    </template>
  </div>
</template>
