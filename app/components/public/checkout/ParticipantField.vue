<script setup lang="ts">
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import { formatMoeda } from '~/utils/format'

const props = defineProps<{
  indice: number
  modelValue: string
  error?: string
  /** Mostra a escolha inteira/meia (evento com meia-entrada ativa). */
  meiaAtiva?: boolean
  meia?: boolean
  preco?: number | null
  precoMeia?: number | null
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
  'update:meia': [value: boolean]
}>()

const opcao =
  'flex-1 rounded-xl border px-3 py-2 text-left text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50'
</script>

<template>
  <FormField :label="`Ingresso ${props.indice + 1}`" required :error="props.error">
    <BaseInput
      :model-value="props.modelValue"
      placeholder="Nome do participante"
      autocomplete="off"
      :invalid="!!props.error"
      @update:model-value="emit('update:modelValue', $event)"
    />
    <div
      v-if="props.meiaAtiva"
      class="mt-2 flex gap-2"
      role="radiogroup"
      :aria-label="`Tipo do ingresso ${props.indice + 1}`"
    >
      <button
        type="button"
        role="radio"
        :aria-checked="!props.meia"
        :class="[opcao, !props.meia ? 'border-amber-400 bg-amber-400/10 text-white' : 'border-zinc-700 text-zinc-400 hover:border-zinc-500']"
        @click="emit('update:meia', false)"
      >
        <span class="font-semibold">Inteira</span>
        <span class="block text-zinc-400">{{ formatMoeda(props.preco ?? 0) }}</span>
      </button>
      <button
        type="button"
        role="radio"
        :aria-checked="!!props.meia"
        :class="[opcao, props.meia ? 'border-amber-400 bg-amber-400/10 text-white' : 'border-zinc-700 text-zinc-400 hover:border-zinc-500']"
        @click="emit('update:meia', true)"
      >
        <span class="font-semibold">Meia-entrada</span>
        <span class="block text-zinc-400">{{ formatMoeda(props.precoMeia ?? 0) }}</span>
      </button>
    </div>
  </FormField>
</template>
