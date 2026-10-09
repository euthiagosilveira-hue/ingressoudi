<script setup lang="ts">
import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import EntryMethodBadge from '~/components/entradas/EntryMethodBadge.vue'
import EntryStatusBadge from '~/components/entradas/EntryStatusBadge.vue'
import { estadoEntrada } from '~/utils/entradas'
import { formatDataHoraCompleta } from '~/utils/format'
import type { EntryListItem } from '~/types/entrada'

const props = defineProps<{
  open: boolean
  entrada: EntryListItem | null
}>()

const emit = defineEmits<{
  close: []
}>()
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Detalhes da entrada"
    :subtitle="props.entrada?.ingressoCodigo ?? ''"
    @close="emit('close')"
  >
    <div v-if="props.entrada" class="space-y-4">
      <dl class="space-y-3 text-sm">
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Participante</dt>
          <dd class="text-right font-medium text-zinc-100">{{ props.entrada.participanteNome }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Evento</dt>
          <dd class="text-right text-zinc-200">{{ props.entrada.eventoNome }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Ingresso</dt>
          <dd class="text-right text-zinc-200">{{ props.entrada.ingressoCodigo }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Pedido</dt>
          <dd class="text-right text-zinc-200">{{ props.entrada.pedidoCodigo }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Método</dt>
          <dd><EntryMethodBadge :metodo="props.entrada.metodo" /></dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Operador</dt>
          <dd class="text-right text-zinc-200">{{ props.entrada.usuarioNome }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="text-zinc-500">Entrada em</dt>
          <dd class="text-right text-zinc-200">
            {{ formatDataHoraCompleta(props.entrada.entradaEm) }}
          </dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Situação</dt>
          <dd><EntryStatusBadge :state="estadoEntrada(props.entrada)" /></dd>
        </div>
      </dl>

      <div
        v-if="props.entrada.anuladaEm"
        class="space-y-3 rounded-xl border border-red-500/30 bg-red-500/5 p-3"
      >
        <p class="text-sm font-semibold text-red-300">Entrada anulada</p>
        <dl class="space-y-3 text-sm">
          <div class="flex items-start justify-between gap-3">
            <dt class="text-zinc-500">Anulada em</dt>
            <dd class="text-right text-zinc-200">
              {{ formatDataHoraCompleta(props.entrada.anuladaEm) }}
            </dd>
          </div>
          <div class="flex items-start justify-between gap-3">
            <dt class="text-zinc-500">Anulada por</dt>
            <dd class="text-right text-zinc-200">
              {{ props.entrada.anuladaPorUsuarioNome ?? '—' }}
            </dd>
          </div>
          <div class="flex flex-col gap-1">
            <dt class="text-zinc-500">Motivo</dt>
            <dd class="text-zinc-200">{{ props.entrada.motivoAnulacao ?? '—' }}</dd>
          </div>
        </dl>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end">
        <AppButton variant="ghost" @click="emit('close')">Fechar</AppButton>
      </div>
    </template>
  </BaseModal>
</template>
