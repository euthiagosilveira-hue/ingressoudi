<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import { excluirEventoPlataforma, obterResumoExclusaoEvento } from '~/services/admin/eventosPlataforma'
import {
  itensExclusao,
  nomeConfere,
  temVendasPagas,
  type ResumoExclusaoEvento
} from '~/utils/excluirEvento'
import { formatMoeda, formatNumero } from '~/utils/format'

const props = defineProps<{
  open: boolean
  eventoId: string
  eventoNome: string
}>()

const emit = defineEmits<{
  close: []
  excluido: [eventoId: string]
}>()

const resumo = ref<ResumoExclusaoEvento | null>(null)
const carregando = ref(false)
const excluindo = ref(false)
const erro = ref('')
const nomeDigitado = ref('')
const confirmaVendas = ref(false)

const comVendas = computed(() => (resumo.value ? temVendasPagas(resumo.value) : false))
const itens = computed(() => (resumo.value ? itensExclusao(resumo.value) : []))
const podeExcluir = computed(
  () =>
    !!resumo.value &&
    !carregando.value &&
    !excluindo.value &&
    nomeConfere(nomeDigitado.value, resumo.value.nome) &&
    (!comVendas.value || confirmaVendas.value)
)

async function carregar() {
  resumo.value = null
  erro.value = ''
  nomeDigitado.value = ''
  confirmaVendas.value = false
  carregando.value = true
  try {
    resumo.value = await obterResumoExclusaoEvento(props.eventoId)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o evento.'
  } finally {
    carregando.value = false
  }
}

watch(
  () => [props.open, props.eventoId] as const,
  ([aberto]) => {
    if (aberto && props.eventoId) void carregar()
  },
  { immediate: true }
)

function fechar() {
  if (excluindo.value) return
  emit('close')
}

async function excluir() {
  if (!podeExcluir.value || !resumo.value) return
  excluindo.value = true
  erro.value = ''
  try {
    await excluirEventoPlataforma(resumo.value.eventoId, comVendas.value && confirmaVendas.value)
    emit('excluido', resumo.value.eventoId)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível excluir o evento.'
  } finally {
    excluindo.value = false
  }
}
</script>

<template>
  <BaseModal :open="props.open" title="Excluir evento" :subtitle="props.eventoNome" @close="fechar">
    <div class="space-y-4 text-sm">
      <div v-if="carregando" class="h-24 animate-pulse rounded-xl bg-zinc-800/60" aria-busy="true" />

      <template v-else-if="resumo">
        <p class="text-zinc-300">
          O evento <span class="font-semibold text-white">{{ resumo.nome }}</span>
          da casa <span class="font-semibold text-white">{{ resumo.organizacaoNome }}</span>
          será apagado de vez. A página pública sai do ar e o link para de funcionar.
        </p>

        <div v-if="itens.length" class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
          <p class="mb-1 text-xs uppercase tracking-wide text-zinc-500">Também será apagado</p>
          <ul class="list-inside list-disc space-y-0.5 text-zinc-300">
            <li v-for="item in itens" :key="item">{{ item }}</li>
          </ul>
        </div>
        <p v-else class="text-zinc-500">O evento não tem pedidos, ingressos nem lista VIP.</p>

        <div
          v-if="comVendas"
          class="space-y-3 rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-red-200"
        >
          <p class="flex gap-2">
            <ExclamationTriangleIcon class="h-5 w-5 shrink-0 text-red-300" />
            <span>
              Este evento tem <strong>{{ formatNumero(resumo.pedidosPagos) }} pedido(s) pago(s)</strong>,
              somando <strong>{{ formatMoeda(resumo.valorPago) }}</strong>
              <template v-if="resumo.pedidosPagosOnline > 0">
                ({{ formatNumero(resumo.pedidosPagosOnline) }} pago(s) por Pix no Mercado Pago)</template>.
              Excluir não devolve dinheiro a ninguém: se for venda de verdade, faça o reembolso antes.
            </span>
          </p>
          <label class="flex cursor-pointer items-start gap-2">
            <input v-model="confirmaVendas" type="checkbox" class="mt-0.5 h-4 w-4 accent-red-500" />
            <span>Entendo. São vendas de teste e podem ser apagadas.</span>
          </label>
        </div>

        <p v-if="resumo.pixPendentes > 0" class="text-xs text-amber-300/90">
          Há {{ formatNumero(resumo.pixPendentes) }} Pix ainda não pago(s). Se alguém pagar depois da exclusão,
          o pagamento aparece em Plataforma &gt; Erros de pagamento.
        </p>

        <div class="space-y-1.5">
          <label for="confirmar-nome-evento" class="block text-xs text-zinc-400">
            Para confirmar, digite o nome do evento: <span class="font-semibold text-zinc-200">{{ resumo.nome }}</span>
          </label>
          <BaseInput id="confirmar-nome-evento" v-model="nomeDigitado" :placeholder="resumo.nome" autocomplete="off" />
        </div>

        <p class="text-xs text-zinc-500">
          Uma cópia do que foi apagado fica guardada no registro de auditoria da plataforma.
        </p>
      </template>

      <p
        v-if="erro"
        role="alert"
        class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        {{ erro }}
      </p>
    </div>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="excluindo" @click="fechar">Cancelar</AppButton>
        <AppButton variant="danger" :disabled="!podeExcluir" @click="excluir">
          {{ excluindo ? 'Excluindo...' : 'Excluir evento' }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
