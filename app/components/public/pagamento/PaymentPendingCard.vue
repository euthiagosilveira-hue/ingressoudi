<script setup lang="ts">
import { computed, ref } from 'vue'
import { ClipboardDocumentIcon } from '@heroicons/vue/24/outline'
import QrcodeVue from 'qrcode.vue'

import PaymentExpiration from '~/components/public/pagamento/PaymentExpiration.vue'
import PaymentStatusBadge from '~/components/public/pagamento/PaymentStatusBadge.vue'
import PaymentSummary from '~/components/public/pagamento/PaymentSummary.vue'
import type { CheckoutPublico } from '~/types/checkoutPagamento'
import type { PaymentStatus } from '~/types/pagamento'
import { valorQrPix } from '~/utils/pagamentos'

interface PixData {
  pixCopyPaste: string | null
  pixQrCode: string | null
  expiresAt: string | null
}

const props = defineProps<{
  checkout: CheckoutPublico
  textoCountdown: string
  tempoEsgotado: boolean
  pix: PixData | null
  pixCarregando?: boolean
  pixErro?: boolean
  verificando?: boolean
}>()

const emit = defineEmits<{
  atualizar: []
  tentarPix: []
}>()

const statusPagamento: PaymentStatus = props.checkout.pagamento?.status ?? 'PENDENTE'

// Enquanto o backend reconcilia/expira, escondemos QR/copia-e-cola e acoes.
const emVerificacao = computed(() => Boolean(props.verificando || props.tempoEsgotado))

const qrSrc = computed(() => {
  const qr = props.pix?.pixQrCode
  if (!qr) return null
  return qr.startsWith('data:') ? qr : `data:image/png;base64,${qr}`
})

const pixCopiaCola = computed(() => valorQrPix(props.pix))
const temPix = computed(() => Boolean(pixCopiaCola.value || qrSrc.value))
const copiado = ref(false)

async function copiar() {
  const codigo = pixCopiaCola.value
  if (!codigo || typeof navigator === 'undefined') return
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(codigo)
    } else {
      copiaLegado(codigo)
    }
    copiado.value = true
    setTimeout(() => {
      copiado.value = false
    }, 2000)
  } catch {
    try {
      copiaLegado(codigo)
      copiado.value = true
      setTimeout(() => {
        copiado.value = false
      }, 2000)
    } catch {
      // silencioso: usuario pode copiar manualmente
    }
  }
}

function copiaLegado(texto: string) {
  const area = document.createElement('textarea')
  area.value = texto
  area.style.position = 'fixed'
  area.style.opacity = '0'
  document.body.appendChild(area)
  area.select()
  document.execCommand('copy')
  document.body.removeChild(area)
}
</script>

<template>
  <section class="space-y-5 rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-lg font-semibold text-white">Pagamento pendente</h2>
      <PaymentStatusBadge :status="statusPagamento" />
    </div>

    <PaymentSummary :checkout="props.checkout" />

    <!-- Verificacao final (tempo local zerou): sem QR, sem copia, sem botao -->
    <div
      v-if="emVerificacao"
      class="rounded-xl border border-zinc-800 bg-zinc-950/40 p-6 text-center"
      aria-busy="true"
    >
      <p class="text-sm font-semibold text-zinc-200">Verificando pagamento...</p>
      <p class="mt-1 text-sm text-zinc-400">Aguarde enquanto confirmamos o status da sua reserva.</p>
    </div>

    <template v-else>
      <div v-if="temPix" class="space-y-4 rounded-xl border border-zinc-800 bg-zinc-950/40 p-4">
        <p class="text-sm font-semibold text-zinc-200">Pagamento via Pix</p>

        <div v-if="pixCopiaCola" class="mx-auto w-full max-w-[240px] rounded-xl bg-white p-3">
          <QrcodeVue
            :value="pixCopiaCola"
            :size="220"
            :margin="2"
            level="M"
            render-as="svg"
            class="mx-auto block h-auto w-full"
          />
        </div>
        <div v-else-if="qrSrc" class="mx-auto w-full max-w-[240px] rounded-xl bg-white p-3">
          <img :src="qrSrc" alt="QR Code Pix" class="h-auto w-full" />
        </div>

        <p class="text-center text-xs text-zinc-500">
          Abra o app do seu banco, escaneie o QR Code ou use o Pix Copia e Cola.
        </p>

        <div v-if="pixCopiaCola" class="space-y-2">
          <p class="text-xs uppercase tracking-wide text-zinc-500">Pix copia e cola</p>
          <p
            class="max-h-24 overflow-y-auto break-all rounded-lg border border-zinc-800 bg-zinc-950 p-3 text-xs text-zinc-300"
          >
            {{ pixCopiaCola }}
          </p>
          <button
            type="button"
            class="flex w-full items-center justify-center gap-2 rounded-xl bg-amber-400 px-6 py-3 text-xs font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60"
            @click="copiar"
          >
            <ClipboardDocumentIcon class="h-4 w-4" />
            {{ copiado ? 'Código Pix copiado.' : 'Copiar código Pix' }}
          </button>
        </div>
      </div>

      <div
        v-else-if="props.pixCarregando"
        class="rounded-xl border border-zinc-800 bg-zinc-950/40 p-4"
        aria-busy="true"
      >
        <p class="text-sm font-semibold text-zinc-200">Pagamento via Pix</p>
        <p class="mt-1 text-sm text-zinc-400">Gerando pagamento Pix...</p>
      </div>

      <div
        v-else-if="props.pixErro"
        class="space-y-2 rounded-xl border border-red-500/40 bg-red-500/5 p-4"
      >
        <p class="text-sm font-semibold text-red-300">
          Não foi possível gerar o pagamento Pix. Tente novamente.
        </p>
        <button
          type="button"
          class="inline-flex items-center justify-center rounded-lg border border-amber-400/60 px-5 py-2.5 text-xs font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400 hover:text-zinc-950"
          @click="emit('tentarPix')"
        >
          Tentar novamente
        </button>
      </div>

      <div v-else class="rounded-xl border border-zinc-800 bg-zinc-950/40 p-4">
        <p class="text-sm font-semibold text-zinc-200">Pagamento via Pix</p>
        <p class="mt-1 text-sm text-zinc-400">
          Estamos preparando o seu pagamento Pix. Use "Atualizar status" em instantes.
        </p>
      </div>

      <PaymentExpiration :texto="props.textoCountdown" />

      <button
        type="button"
        class="flex w-full items-center justify-center rounded-xl border border-zinc-700 px-6 py-3 text-xs font-bold uppercase tracking-wide text-zinc-300 transition-colors duration-150 hover:border-zinc-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        @click="emit('atualizar')"
      >
        Atualizar status
      </button>
    </template>
  </section>
</template>
