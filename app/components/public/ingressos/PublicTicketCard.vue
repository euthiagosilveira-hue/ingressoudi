<script setup lang="ts">
import { computed, ref } from 'vue'
import { ArrowUpTrayIcon } from '@heroicons/vue/24/outline'

import PublicTicketQr from '~/components/public/ingressos/PublicTicketQr.vue'
import { criarCompartilhamento } from '~/services/public/compartilhamento'
import type { PublicTicket } from '~/types/publicIngressos'
import { formatDataHoraCompleta } from '~/utils/format'
import { qrUtilizavel, rotuloStatusIngresso } from '~/utils/publicIngressos'
import { compartilharOuCopiar } from '~/utils/share'

const props = defineProps<{
  ticket: PublicTicket
  eventoNome: string
  eventoInicioEm: string
  eventoLocal: string
  checkoutToken?: string | null
  recoveryToken?: string | null
}>()

const podeMostrarQr = computed(
  () => qrUtilizavel(props.ticket.status) && Boolean(props.ticket.qrToken)
)

const badgeClasses = computed(() => {
  switch (props.ticket.status) {
    case 'VALIDO':
      return 'border-green-500/50 bg-green-500/10 text-green-300'
    case 'UTILIZADO':
      return 'border-zinc-600 bg-zinc-800 text-zinc-300'
    case 'CANCELADO':
      return 'border-red-500/40 bg-red-500/10 text-red-300'
    default:
      return 'border-amber-500/40 bg-amber-500/10 text-amber-300'
  }
})

const compartilhando = ref(false)
const feedback = ref('')
const feedbackErro = ref(false)

async function compartilhar() {
  if (compartilhando.value) return
  feedback.value = ''
  feedbackErro.value = false

  if (!props.checkoutToken && !props.recoveryToken) {
    feedback.value = 'Não foi possível compartilhar este ingresso.'
    feedbackErro.value = true
    return
  }

  compartilhando.value = true
  try {
    const shareUrl = await criarCompartilhamento({
      ingressoId: props.ticket.ingressoId,
      checkoutToken: props.checkoutToken ?? null,
      recoveryToken: props.recoveryToken ?? null
    })
    const resultado = await compartilharOuCopiar({ url: shareUrl, eventoNome: props.eventoNome })
    if (resultado === 'copiado') {
      feedback.value = 'Link copiado'
    } else if (resultado === 'falha') {
      feedback.value = 'Não foi possível compartilhar.'
      feedbackErro.value = true
    }
  } catch {
    feedback.value = 'Não foi possível compartilhar.'
    feedbackErro.value = true
  } finally {
    compartilhando.value = false
  }
}
</script>

<template>
  <article class="space-y-4 rounded-2xl border border-zinc-800 bg-zinc-900 p-5">
    <div class="flex items-start justify-between gap-3">
      <div>
        <p class="text-base font-semibold text-white">{{ props.ticket.participanteNome }}</p>
        <p class="text-xs text-zinc-500">Ingresso {{ props.ticket.codigo }}</p>
      </div>
      <span class="shrink-0 rounded-full border px-3 py-1 text-xs font-semibold" :class="badgeClasses">
        {{ rotuloStatusIngresso(props.ticket.status) }}
      </span>
    </div>

    <div class="rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-xs text-zinc-400">
      <p class="font-medium text-zinc-200">{{ props.eventoNome }}</p>
      <p>{{ formatDataHoraCompleta(props.eventoInicioEm) }}</p>
      <p>{{ props.eventoLocal }}</p>
    </div>

    <div v-if="podeMostrarQr" class="space-y-3">
      <PublicTicketQr :value="props.ticket.qrToken as string" />
      <p class="text-center text-sm text-zinc-400">Apresente este QR Code na entrada.</p>

      <button
        type="button"
        :disabled="compartilhando"
        class="flex w-full items-center justify-center gap-2 rounded-xl border border-amber-400/60 px-6 py-3 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 disabled:pointer-events-none disabled:opacity-60"
        @click="compartilhar"
      >
        <ArrowUpTrayIcon class="h-4 w-4" />
        {{ compartilhando ? 'Gerando link...' : 'Compartilhar ingresso' }}
      </button>

      <p
        v-if="feedback"
        class="text-center text-xs"
        :class="feedbackErro ? 'text-red-300' : 'text-green-300'"
      >
        {{ feedback }}
      </p>
    </div>

    <p
      v-else-if="props.ticket.status === 'UTILIZADO'"
      class="rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-center text-sm font-semibold text-zinc-300"
    >
      Ingresso utilizado
    </p>

    <p
      v-else
      class="rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-center text-sm text-zinc-500"
    >
      Este ingresso não está disponível para entrada.
    </p>
  </article>
</template>
