<script setup lang="ts">
import ParticipantField from '~/components/public/checkout/ParticipantField.vue'
import type { CheckoutParticipant } from '~/types/checkout'
import { AVISO_MEIA_ENTRADA } from '~/utils/meiaEntrada'

const props = defineProps<{
  participantes: CheckoutParticipant[]
  erros: string[]
  meiaAtiva?: boolean
  preco?: number | null
  precoMeia?: number | null
}>()

const emit = defineEmits<{
  'update:nome': [{ indice: number; valor: string }]
  'update:meia': [{ indice: number; valor: boolean }]
}>()
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <div>
      <h2 class="text-lg font-semibold text-white">Participantes</h2>
      <p class="mt-1 text-sm text-zinc-400">
        Informe o nome de cada pessoa que vai usar um ingresso<template v-if="props.meiaAtiva">
          e se o ingresso é inteira ou meia-entrada</template>.
      </p>
    </div>

    <p
      v-if="props.meiaAtiva"
      class="rounded-xl border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-200"
    >
      {{ AVISO_MEIA_ENTRADA }}
    </p>

    <div class="space-y-4">
      <ParticipantField
        v-for="(participante, indice) in props.participantes"
        :key="indice"
        :indice="indice"
        :model-value="participante.nome"
        :error="props.erros[indice]"
        :meia-ativa="props.meiaAtiva"
        :meia="participante.meia === true"
        :preco="props.preco"
        :preco-meia="props.precoMeia"
        @update:model-value="emit('update:nome', { indice, valor: $event })"
        @update:meia="emit('update:meia', { indice, valor: $event })"
      />
    </div>
  </section>
</template>
