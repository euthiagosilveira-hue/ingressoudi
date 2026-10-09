<script setup lang="ts">
import { computed } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import LotActivationBadge from '~/components/lotes/LotActivationBadge.vue'
import LotStatusBadge from '~/components/lotes/LotStatusBadge.vue'
import { formatDataHora, formatMoeda, formatNumero } from '~/utils/format'
import type { LotListItem } from '~/types/lote'

const props = defineProps<{
  open: boolean
  lote: LotListItem | null
}>()

const emit = defineEmits<{
  close: []
}>()

const esgotado = computed(() => (props.lote ? props.lote.disponiveis === 0 : false))

const datas = computed(() => {
  if (!props.lote) return []
  const itens: Array<{ label: string; valor: string }> = []
  if (props.lote.ativacaoEm) {
    itens.push({ label: 'Ativação programada', valor: formatDataHora(props.lote.ativacaoEm) })
  }
  if (props.lote.ativadoEm) {
    itens.push({ label: 'Ativado em', valor: formatDataHora(props.lote.ativadoEm) })
  }
  if (props.lote.encerradoEm) {
    itens.push({ label: 'Encerrado em', valor: formatDataHora(props.lote.encerradoEm) })
  }
  return itens
})
</script>

<template>
  <BaseModal
    :open="props.open"
    :title="props.lote?.nome ?? 'Detalhes do lote'"
    subtitle="Detalhes do lote"
    @close="emit('close')"
  >
    <div v-if="props.lote" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm text-zinc-400">Status</span>
        <LotStatusBadge :status="props.lote.status" />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
          <p class="text-[11px] uppercase tracking-wide text-zinc-500">Preço</p>
          <p class="mt-0.5 text-lg font-bold text-amber-400">{{ formatMoeda(props.lote.preco) }}</p>
        </div>
        <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
          <p class="text-[11px] uppercase tracking-wide text-zinc-500">Ordem</p>
          <p class="mt-0.5 text-lg font-bold text-white">{{ props.lote.ordem }}º</p>
        </div>
      </div>

      <dl class="space-y-2 text-sm">
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Quantidade</dt>
          <dd class="text-zinc-200">{{ formatNumero(props.lote.quantidade) }} ingressos</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Vendidos</dt>
          <dd class="text-zinc-200">{{ formatNumero(props.lote.vendidos) }}</dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Disponíveis</dt>
          <dd :class="esgotado ? 'text-zinc-500' : 'text-zinc-200'">
            {{ formatNumero(props.lote.disponiveis) }}<span v-if="esgotado"> · Esgotado</span>
          </dd>
        </div>
        <div class="flex items-center justify-between gap-3">
          <dt class="text-zinc-500">Ativação</dt>
          <dd><LotActivationBadge :tipo="props.lote.tipoAtivacao" /></dd>
        </div>
        <div
          v-for="item in datas"
          :key="item.label"
          class="flex items-center justify-between gap-3"
        >
          <dt class="text-zinc-500">{{ item.label }}</dt>
          <dd class="text-zinc-200">{{ item.valor }}</dd>
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
