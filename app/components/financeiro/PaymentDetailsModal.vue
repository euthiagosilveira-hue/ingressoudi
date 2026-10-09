<script setup lang="ts">
import { computed } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import PaymentProviderBadge from '~/components/financeiro/PaymentProviderBadge.vue'
import PaymentStatusBadge from '~/components/financeiro/PaymentStatusBadge.vue'
import { formatDataHoraCompleta, formatMoeda } from '~/utils/format'
import type { PaymentListItem } from '~/types/pagamento'

const props = defineProps<{
  open: boolean
  pagamento: PaymentListItem | null
}>()

const emit = defineEmits<{
  close: []
}>()

const liquido = computed(() => {
  if (!props.pagamento) return 0
  return props.pagamento.valor - props.pagamento.valorReembolsado
})

const mensagemStatus = computed(() => {
  if (!props.pagamento) return ''
  switch (props.pagamento.status) {
    case 'PENDENTE':
      return 'Aguardando pagamento.'
    case 'APROVADO':
      return 'Pagamento aprovado.'
    case 'REJEITADO':
      return 'Pagamento não aprovado.'
    case 'CANCELADO':
      return 'Pagamento cancelado.'
    case 'EXPIRADO':
      return 'Pagamento expirado.'
    case 'REEMBOLSADO':
      return 'Pagamento reembolsado.'
    default:
      return ''
  }
})
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Detalhes do pagamento"
    :subtitle="props.pagamento?.pedidoCodigo ?? ''"
    @close="emit('close')"
  >
    <div v-if="props.pagamento" class="space-y-5">
      <div class="flex flex-wrap items-center gap-2">
        <PaymentStatusBadge :status="props.pagamento.status" />
        <PaymentProviderBadge :provider="props.pagamento.provider" />
      </div>

      <p class="text-sm text-zinc-400">{{ mensagemStatus }}</p>

      <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <dt class="text-xs text-zinc-500">Valor</dt>
          <dd class="text-sm font-semibold text-amber-400">
            {{ formatMoeda(props.pagamento.valor) }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Pedido</dt>
          <dd class="text-sm text-zinc-200">{{ props.pagamento.pedidoCodigo }}</dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Comprador</dt>
          <dd class="text-sm text-zinc-200">{{ props.pagamento.compradorNome }}</dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Evento</dt>
          <dd class="text-sm text-zinc-200">{{ props.pagamento.eventoNome }}</dd>
        </div>
      </dl>

      <div v-if="props.pagamento.status === 'REEMBOLSADO'" class="space-y-3 rounded-xl border border-violet-500/30 bg-violet-500/5 p-3">
        <p class="text-sm font-semibold text-violet-300">Pagamento reembolsado</p>
        <dl class="space-y-2 text-sm">
          <div class="flex items-center justify-between gap-3">
            <dt class="text-zinc-500">Valor original</dt>
            <dd class="text-zinc-200">{{ formatMoeda(props.pagamento.valor) }}</dd>
          </div>
          <div class="flex items-center justify-between gap-3">
            <dt class="text-zinc-500">Valor reembolsado</dt>
            <dd class="text-zinc-200">{{ formatMoeda(props.pagamento.valorReembolsado) }}</dd>
          </div>
          <div class="flex items-center justify-between gap-3">
            <dt class="text-zinc-500">Valor líquido</dt>
            <dd class="font-semibold text-zinc-100">{{ formatMoeda(liquido) }}</dd>
          </div>
          <div v-if="props.pagamento.reembolsadoEm" class="flex items-center justify-between gap-3">
            <dt class="text-zinc-500">Data do reembolso</dt>
            <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.reembolsadoEm) }}</dd>
          </div>
        </dl>
      </div>

      <div class="space-y-2 border-t border-zinc-800 pt-4">
        <p class="text-[11px] uppercase tracking-wide text-zinc-500">
          Informações da transação
        </p>
        <p class="break-all text-xs text-zinc-400">
          ID da transação: <span class="text-zinc-300">{{ props.pagamento.transactionId }}</span>
        </p>
        <p class="break-all text-xs text-zinc-400">
          ID da cobrança: <span class="text-zinc-300">{{ props.pagamento.chargeId }}</span>
        </p>
        <p class="break-all text-xs text-zinc-400">
          Referência externa:
          <span class="text-zinc-300">{{ props.pagamento.externalReference }}</span>
        </p>
      </div>

      <dl class="space-y-2 border-t border-zinc-800 pt-4 text-sm">
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Criado em</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.criadoEm) }}</dd>
        </div>
        <div v-if="props.pagamento.expiraEm" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Expira em</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.expiraEm) }}</dd>
        </div>
        <div v-if="props.pagamento.confirmadoEm" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Confirmado em</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.confirmadoEm) }}</dd>
        </div>
        <div v-if="props.pagamento.canceladoEm" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Cancelado em</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.canceladoEm) }}</dd>
        </div>
        <div v-if="props.pagamento.reembolsadoEm" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Reembolsado em</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(props.pagamento.reembolsadoEm) }}</dd>
        </div>
        <div v-if="props.pagamento.valorReembolsado > 0" class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Valor reembolsado</dt>
          <dd class="text-zinc-200">{{ formatMoeda(props.pagamento.valorReembolsado) }}</dd>
        </div>
      </dl>
    </div>

    <template #footer>
      <div class="flex justify-end">
        <AppButton variant="ghost" @click="emit('close')">Fechar</AppButton>
      </div>
    </template>
  </BaseModal>
</template>
