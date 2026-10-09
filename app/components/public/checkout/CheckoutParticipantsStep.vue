<script setup lang="ts">
import ParticipantField from '~/components/public/checkout/ParticipantField.vue'
import type { CheckoutParticipant } from '~/types/checkout'

const props = defineProps<{
  participantes: CheckoutParticipant[]
  erros: string[]
}>()

const emit = defineEmits<{
  'update:nome': [{ indice: number; valor: string }]
}>()
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <div>
      <h2 class="text-lg font-semibold text-white">Participantes</h2>
      <p class="mt-1 text-sm text-zinc-400">
        Informe o nome de cada pessoa que vai usar um ingresso.
      </p>
    </div>

    <div class="space-y-4">
      <ParticipantField
        v-for="(participante, indice) in props.participantes"
        :key="indice"
        :indice="indice"
        :model-value="participante.nome"
        :error="props.erros[indice]"
        @update:model-value="emit('update:nome', { indice, valor: $event })"
      />
    </div>
  </section>
</template>
