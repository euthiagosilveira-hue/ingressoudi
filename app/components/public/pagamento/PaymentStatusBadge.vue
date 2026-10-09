<script setup lang="ts">
import { computed } from 'vue'
import type { PaymentStatus } from '~/types/pagamento'

const props = defineProps<{
  status: PaymentStatus
}>()

const mapa: Record<PaymentStatus, { label: string; classes: string }> = {
  PENDENTE: {
    label: 'Pendente',
    classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300'
  },
  APROVADO: {
    label: 'Aprovado',
    classes: 'border-green-500/30 bg-green-500/10 text-green-300'
  },
  REJEITADO: {
    label: 'Não aprovado',
    classes: 'border-red-500/30 bg-red-500/10 text-red-300'
  },
  CANCELADO: {
    label: 'Cancelado',
    classes: 'border-zinc-600/40 bg-zinc-800/70 text-zinc-300'
  },
  EXPIRADO: {
    label: 'Expirado',
    classes: 'border-zinc-700/40 bg-zinc-800/50 text-zinc-400'
  },
  REEMBOLSADO: {
    label: 'Reembolsado',
    classes: 'border-violet-500/30 bg-violet-500/10 text-violet-300'
  }
}

const info = computed(() => mapa[props.status])
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-[11px] font-bold uppercase tracking-wide"
    :class="info.classes"
  >
    <span class="h-1.5 w-1.5 rounded-full bg-current opacity-80"></span>
    {{ info.label }}
  </span>
</template>
