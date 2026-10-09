<script setup lang="ts">
import { watch } from 'vue'

import GateEmptyState from '~/components/portaria/GateEmptyState.vue'
import GateEventSelector from '~/components/portaria/GateEventSelector.vue'
import GateHeader from '~/components/portaria/GateHeader.vue'
import GateModeTabs from '~/components/portaria/GateModeTabs.vue'
import GateNameSearchPanel from '~/components/portaria/GateNameSearchPanel.vue'
import GateQrScanner from '~/components/portaria/GateQrScanner.vue'
import { useGate } from '~/composables/useGate'
import { useGateConectividade } from '~/composables/useGateConectividade'
import { useGateSession } from '~/composables/useGateSession'
import type { EventListItem } from '~/types/evento'

const props = defineProps<{
  eventos: EventListItem[]
}>()

// useGate e usado apenas para a selecao do evento (fluxo real da portaria).
const { eventosOperacionais, eventoId, eventoAtual, modo, selecionarEvento, definirModo } =
  useGate(props.eventos)

// Sessao local (contador + ultima entrada). Zera ao trocar de evento.
const { total, ultima, resetar } = useGateSession()
watch(eventoId, () => resetar())

// Indicador de conectividade (nao dispara retry ao voltar online).
const { online } = useGateConectividade()
</script>

<template>
  <div class="mx-auto w-full max-w-5xl space-y-5">
    <GateHeader :evento="eventoAtual" :total-entradas="total" :ultima="ultima" />

    <p
      v-if="!online"
      role="status"
      aria-live="polite"
      class="flex items-center gap-2 rounded-xl border border-amber-400/40 bg-amber-400/10 px-3 py-2 text-xs font-semibold text-amber-300"
    >
      <span class="h-2 w-2 rounded-full bg-amber-400"></span>
      Sem internet — verifique a rede.
    </p>

    <GateEventSelector
      :model-value="eventoId"
      :eventos="eventosOperacionais"
      :evento="eventoAtual"
      @update:model-value="selecionarEvento"
    />

    <GateEmptyState v-if="!eventoAtual" />

    <div v-else class="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
      <div class="space-y-5">
        <GateModeTabs :model-value="modo" @update:model-value="definirModo" />

        <GateQrScanner v-if="modo === 'QR'" :evento-id="eventoId" />
        <GateNameSearchPanel v-else :evento-id="eventoId" />
      </div>
    </div>
  </div>
</template>
