<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import OrderBuyerCard from '~/components/pedidos/OrderBuyerCard.vue'
import OrderDetailActions from '~/components/pedidos/OrderDetailActions.vue'
import OrderDetailHeader from '~/components/pedidos/OrderDetailHeader.vue'
import OrderEventCard from '~/components/pedidos/OrderEventCard.vue'
import OrderFinancialCard from '~/components/pedidos/OrderFinancialCard.vue'
import OrderOverviewCard from '~/components/pedidos/OrderOverviewCard.vue'
import OrderPaymentCard from '~/components/pedidos/OrderPaymentCard.vue'
import OrderTicketsCard from '~/components/pedidos/OrderTicketsCard.vue'
import OrderTimeline from '~/components/pedidos/OrderTimeline.vue'
import { reembolsarPedido } from '~/services/admin/pedidos'
import type { OrderDetail } from '~/types/pedido'
import { formatMoeda } from '~/utils/format'
import { situacaoPrazoDesistencia, temIngressoUtilizado } from '~/utils/reembolso'

const props = defineProps<{
  pedido: OrderDetail
}>()

const emit = defineEmits<{
  atualizado: []
}>()

const route = useRoute()

const confirmarReembolso = ref(false)
const motivoReembolso = ref('')
const reembolsando = ref(false)
const erroReembolso = ref('')

const ehPix = computed(() => props.pedido.pagamento?.provider === 'MERCADO_PAGO')
const valorReembolso = computed(() => props.pedido.pagamento?.valor ?? props.pedido.valorTotal)
const prazo = computed(() => situacaoPrazoDesistencia(props.pedido.pagoEm, props.pedido.eventoInicioEm))
const bloqueadoPorEntrada = computed(() => temIngressoUtilizado(props.pedido.ingressos))

const temReembolso = computed(() => (props.pedido.pagamento?.valorReembolsado ?? 0) > 0)

function rolarPara(id: string) {
  if (typeof document === 'undefined') return
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

function acao(action: string) {
  switch (action) {
    case 'ver-pagamento':
      rolarPara('order-payment')
      break
    case 'ver-ingressos':
      rolarPara('order-tickets')
      break
    case 'ver-historico':
      rolarPara('order-timeline')
      break
    case 'ver-reembolso':
      rolarPara('order-payment')
      break
    case 'solicitar-reembolso':
      abrirReembolso()
      break
  }
}

function abrirReembolso() {
  motivoReembolso.value = prazo.value.dentroDoPrazo ? 'Desistência do comprador no prazo' : ''
  erroReembolso.value = ''
  confirmarReembolso.value = true
}

async function confirmarSolicitacaoReembolso() {
  if (!motivoReembolso.value.trim()) {
    erroReembolso.value = 'Informe o motivo do reembolso.'
    return
  }
  reembolsando.value = true
  erroReembolso.value = ''
  try {
    const r = await reembolsarPedido(props.pedido.id, motivoReembolso.value.trim())
    confirmarReembolso.value = false
    toast.success(
      r.manual
        ? 'Pedido cancelado. Registre a devolução em dinheiro ao comprador.'
        : r.emProcesso
          ? 'Reembolso enviado: o Mercado Pago está processando a devolução do Pix.'
          : `Reembolso de ${formatMoeda(r.valor)} concluído. Os ingressos foram cancelados.`
    )
    emit('atualizado')
  } catch (e) {
    erroReembolso.value = e instanceof Error ? e.message : 'Não foi possível concluir o reembolso.'
  } finally {
    reembolsando.value = false
  }
}

function visualizarIngresso() {
  toast.info('Visualização do ingresso será implementada na próxima etapa.')
}

onMounted(() => {
  const hash = route.hash.replace('#', '')
  if (hash) rolarPara(hash)
})
</script>

<template>
  <div class="mx-auto w-full max-w-6xl space-y-6">
    <OrderDetailHeader :pedido="props.pedido">
      <template #actions>
        <OrderDetailActions
          :status="props.pedido.status"
          :tem-reembolso="temReembolso"
          @action="acao"
        />
      </template>
    </OrderDetailHeader>

    <div class="grid grid-cols-1 gap-5 lg:grid-cols-3">
      <div class="space-y-5 lg:col-span-2">
        <OrderOverviewCard :pedido="props.pedido" />
        <OrderTicketsCard :pedido="props.pedido" @visualizar="visualizarIngresso" />
        <OrderTimeline :eventos="props.pedido.historico" />
      </div>

      <div class="space-y-5">
        <OrderBuyerCard :pedido="props.pedido" />
        <OrderEventCard :pedido="props.pedido" />
        <OrderFinancialCard :pedido="props.pedido" />
        <OrderPaymentCard :pedido="props.pedido" />
      </div>
    </div>

    <BaseModal
      :open="confirmarReembolso"
      title="Reembolsar pedido"
      :subtitle="`Pedido ${props.pedido.codigo} · ${props.pedido.compradorNome}`"
      @close="!reembolsando && (confirmarReembolso = false)"
    >
      <div class="space-y-4 text-sm">
        <div class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
          <p class="text-xs uppercase tracking-wide text-zinc-500">Valor devolvido ao comprador</p>
          <p class="mt-1 text-2xl font-bold text-white">{{ formatMoeda(valorReembolso) }}</p>
          <p class="mt-1 text-xs text-zinc-400">
            Reembolso total (ingressos + taxa de serviço).
            {{
              ehPix
                ? 'O Pix volta para a conta de quem pagou, saindo da conta Mercado Pago da casa.'
                : 'Venda sem Pix: faça a devolução em dinheiro; aqui apenas registramos.'
            }}
          </p>
        </div>

        <p
          v-if="bloqueadoPorEntrada"
          role="alert"
          class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-red-300"
        >
          Este pedido tem ingresso que já entrou na portaria e não pode ser reembolsado.
        </p>

        <p
          v-else
          class="rounded-xl border p-3 text-xs"
          :class="
            prazo.dentroDoPrazo
              ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
              : 'border-amber-400/30 bg-amber-400/10 text-amber-100'
          "
        >
          <strong>{{ prazo.dentroDoPrazo ? 'Dentro do prazo de desistência.' : 'Fora do prazo de desistência.' }}</strong>
          {{ prazo.dentroDoPrazo ? 'O comprador tem direito ao reembolso pela política.' : prazo.motivo + ' O reembolso fica a seu critério (por exemplo, evento cancelado ou alterado).' }}
        </p>

        <BaseTextarea
          v-model="motivoReembolso"
          label="Motivo"
          :rows="3"
          :maxlength="300"
          placeholder="Ex.: desistência do comprador, evento cancelado..."
          :disabled="reembolsando || bloqueadoPorEntrada"
        />

        <p class="text-xs text-zinc-500">
          Os ingressos serão cancelados e deixarão de valer na portaria. Esta ação não pode ser desfeita.
        </p>

        <p v-if="erroReembolso" role="alert" class="rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-red-300">
          {{ erroReembolso }}
        </p>
      </div>

      <template #footer>
        <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <AppButton variant="ghost" :disabled="reembolsando" @click="confirmarReembolso = false">Voltar</AppButton>
          <AppButton
            variant="danger"
            :disabled="reembolsando || bloqueadoPorEntrada"
            @click="confirmarSolicitacaoReembolso"
          >
            {{ reembolsando ? 'Reembolsando...' : `Reembolsar ${formatMoeda(valorReembolso)}` }}
          </AppButton>
        </div>
      </template>
    </BaseModal>
  </div>
</template>
