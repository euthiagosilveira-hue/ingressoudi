<script setup lang="ts">
import { ref } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import EventLotsModal from '~/components/eventos/EventLotsModal.vue'
import FormField from '~/components/FormField.vue'
import type { EventFormErrors, EventFormValue } from '~/types/evento'

const props = defineProps<{
  value: EventFormValue
  errors: EventFormErrors
  eventoId?: string | null
  eventoNome?: string
}>()

const modalLotesAberto = ref(false)

function abrirModalLotes() {
  if (!props.eventoId) return
  modalLotesAberto.value = true
}

function definirNumero(campo: 'capacidadeTotal' | 'estoqueAntecipado', bruto: string) {
  props.value[campo] = bruto === '' ? null : Number(bruto)
}
</script>

<template>
  <BaseCard class="space-y-5">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      4. Capacidade
    </h2>

    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <FormField
        label="Capacidade total"
        required
        :error="errors.capacidadeTotal"
        hint="Limite físico máximo do evento."
      >
        <BaseInput
          type="number"
          :model-value="props.value.capacidadeTotal ?? ''"
          :invalid="!!errors.capacidadeTotal"
          @update:model-value="(valor) => definirNumero('capacidadeTotal', valor)"
        />
      </FormField>

      <FormField
        label="Ingressos disponíveis na pré-venda"
        required
        :error="errors.estoqueAntecipado"
        hint="Quantidade máxima disponibilizada para venda antecipada."
      >
        <BaseInput
          type="number"
          :model-value="props.value.estoqueAntecipado ?? ''"
          :invalid="!!errors.estoqueAntecipado"
          @update:model-value="(valor) => definirNumero('estoqueAntecipado', valor)"
        />
      </FormField>
    </div>

    <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
      <p class="text-sm font-medium text-white">Preços e lotes</p>
      <p class="mt-1 text-sm text-zinc-400">
        Os preços dos ingressos serão configurados nos lotes do evento.
      </p>
      <div class="mt-3 flex flex-wrap items-center gap-3">
        <AppButton variant="outline" size="sm" :disabled="!props.eventoId" @click="abrirModalLotes">
          Configurar lotes
        </AppButton>
        <span v-if="!props.eventoId" class="text-xs text-zinc-500">
          Salve o evento primeiro para configurar os lotes.
        </span>
      </div>
    </div>

    <p class="text-xs text-zinc-500">
      Limite atual por compra:
      <span class="text-zinc-400">Até 10 ingressos por pedido.</span>
    </p>
  </BaseCard>

  <EventLotsModal
    v-if="modalLotesAberto && props.eventoId"
    :open="modalLotesAberto"
    :evento-id="props.eventoId"
    :evento-nome="props.eventoNome"
    @close="modalLotesAberto = false"
  />
</template>
