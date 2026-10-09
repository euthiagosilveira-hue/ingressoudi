<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { toast } from 'vue3-toastify'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import FormField from '~/components/FormField.vue'
import PageHeader from '~/components/PageHeader.vue'
import { criarVendaManualAdmin, listarEventosVendaManualAdmin } from '~/services/admin/vendaManual'
import type { SelectOption } from '~/types/ui'
import type {
  CriarVendaManualResult,
  EventoVendaManual,
  TipoVendaManual,
  VendaManualForm
} from '~/types/vendaManual'
import { formatData, formatMoeda } from '~/utils/format'
import {
  ajustarParticipantes,
  calcularTotalVendaManual,
  loteSelecionado,
  montarPayloadVendaManual,
  validarVendaManual,
  valorUnitarioEfetivo,
  VENDA_MANUAL_QUANTIDADE_MAX
} from '~/utils/vendaManual'

definePageMeta({
  title: 'Nova venda manual',
  description: 'Registre uma venda presencial recebida em dinheiro.',
  layout: 'admin-layout',
  sidebarActive: 'Pedidos',
  middleware: ['admin-auth']
})

const carregando = ref(true)
const erroCarregar = ref('')
const eventos = ref<EventoVendaManual[]>([])
const enviando = ref(false)
const confirmarAberto = ref(false)
const resultado = ref<CriarVendaManualResult | null>(null)
const erros = reactive<Record<string, string>>({})

const form = reactive<VendaManualForm>({
  eventoId: '',
  tipo: 'LOTE',
  loteId: '',
  compradorNome: '',
  compradorTelefone: '',
  compradorEmail: '',
  quantidade: 1,
  valorUnitario: '',
  participantes: ['']
})

const tipoOptions: SelectOption[] = [
  { value: 'LOTE', label: 'Venda por lote' },
  { value: 'AVULSO', label: 'Valor especial' }
]

const eventoSelecionado = computed(
  () => eventos.value.find((evento) => evento.id === form.eventoId) ?? null
)
const lotesAtivos = computed(() => eventoSelecionado.value?.lotesAtivos ?? [])
const loteAtual = computed(() => loteSelecionado(form, eventoSelecionado.value))
const precoUnitario = computed(() => valorUnitarioEfetivo(form, eventoSelecionado.value))
const total = computed(() => calcularTotalVendaManual(precoUnitario.value, form.quantidade))
const disponibilidadeLote = computed(() => loteAtual.value?.disponiveis ?? 0)
const disponibilidadeEvento = computed(() => eventoSelecionado.value?.disponiveisEvento ?? 0)

const eventoOptions = computed<SelectOption[]>(() => [
  { value: '', label: 'Selecione um evento' },
  ...eventos.value.map((evento) => ({
    value: evento.id,
    label: `${evento.nome} — ${formatData(evento.inicioEm)} (${evento.status})`
  }))
])

const loteOptions = computed<SelectOption[]>(() => {
  const opcoes = lotesAtivos.value.map((lote) => ({
    value: lote.id,
    label: `${lote.nome} — ${formatMoeda(lote.preco)}`
  }))
  if (opcoes.length === 0) return [{ value: '', label: 'Nenhum lote ativo' }]
  if (opcoes.length === 1) return opcoes
  return [{ value: '', label: 'Selecione um lote' }, ...opcoes]
})

const quantidadeOptions: SelectOption[] = Array.from(
  { length: VENDA_MANUAL_QUANTIDADE_MAX },
  (_, indice) => ({ value: String(indice + 1), label: String(indice + 1) })
)

const quantidadeSelecionada = computed({
  get: () => String(form.quantidade),
  set: (valor: string) => {
    form.quantidade = Number(valor)
  }
})

function rotuloTipo(tipo: TipoVendaManual): string {
  return tipo === 'AVULSO' ? 'Valor especial' : 'Venda por lote'
}

function sincronizarLote() {
  if (form.tipo !== 'LOTE') return
  if (!lotesAtivos.value.some((lote) => lote.id === form.loteId)) {
    form.loteId = lotesAtivos.value[0]?.id ?? ''
  }
}

watch(
  () => form.eventoId,
  () => {
    form.loteId = ''
    sincronizarLote()
    form.participantes = ajustarParticipantes([], form.quantidade, form.compradorNome)
  }
)

watch(
  () => form.tipo,
  () => {
    sincronizarLote()
  }
)

watch(
  () => form.quantidade,
  (quantidade) => {
    form.participantes = ajustarParticipantes(form.participantes, quantidade, form.compradorNome)
    if (quantidade === 1 && !form.participantes[0]?.trim()) {
      form.participantes[0] = form.compradorNome
    }
  }
)

watch(
  () => form.compradorNome,
  (nome) => {
    if (form.quantidade === 1 && !form.participantes[0]?.trim()) {
      form.participantes[0] = nome
    }
  }
)

function limparErros() {
  for (const chave of Object.keys(erros)) delete erros[chave]
}

function revisar() {
  limparErros()
  const validacao = validarVendaManual(form, eventoSelecionado.value)
  Object.assign(erros, validacao)
  if (Object.keys(validacao).length > 0) return
  confirmarAberto.value = true
}

async function confirmarVenda() {
  if (enviando.value) return
  enviando.value = true
  try {
    resultado.value = await criarVendaManualAdmin(montarPayloadVendaManual(form))
    confirmarAberto.value = false
    toast.success('Venda realizada com sucesso.')
  } catch (erro) {
    confirmarAberto.value = false
    toast.error(erro instanceof Error ? erro.message : 'Não foi possível registrar a venda manual.')
  } finally {
    enviando.value = false
  }
}

function novaVenda() {
  Object.assign(form, {
    eventoId: '',
    tipo: 'LOTE',
    loteId: '',
    compradorNome: '',
    compradorTelefone: '',
    compradorEmail: '',
    quantidade: 1,
    valorUnitario: '',
    participantes: ['']
  })
  resultado.value = null
  limparErros()
}

onMounted(async () => {
  try {
    eventos.value = await listarEventosVendaManualAdmin()
  } catch (erro) {
    erroCarregar.value =
      erro instanceof Error ? erro.message : 'Não foi possível carregar os eventos.'
  } finally {
    carregando.value = false
  }
})
</script>

<template>
  <div class="space-y-6">
    <PageHeader
      title="Nova venda manual"
      subtitle="Registre uma venda presencial recebida em dinheiro."
    >
      <template #actions>
        <AppButton variant="ghost" to="/pedidos">Voltar para pedidos</AppButton>
      </template>
    </PageHeader>

    <BaseCard v-if="carregando" class="text-sm text-zinc-400">Carregando eventos…</BaseCard>

    <BaseCard v-else-if="erroCarregar" class="space-y-3">
      <p class="text-sm text-red-400">{{ erroCarregar }}</p>
      <AppButton variant="outline" to="/pedidos">Voltar para pedidos</AppButton>
    </BaseCard>

    <BaseCard v-else-if="resultado" class="space-y-6">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold text-white">Venda realizada com sucesso.</h2>
        <p class="text-sm text-zinc-400">
          Pedido
          <span class="font-semibold text-amber-400">{{ resultado.codigoPedido }}</span>
          • {{ rotuloTipo(resultado.tipoPreco) }} • {{ resultado.quantidade }} ingresso(s) •
          {{ formatMoeda(resultado.valorTotal) }}
        </p>
        <p class="text-xs text-zinc-500">Forma de pagamento: Dinheiro (recebido).</p>
      </div>

      <div class="flex flex-col gap-3 sm:flex-row">
        <AppButton variant="primary" :to="`/pedidos/${resultado.pedidoId}`">Ver pedido</AppButton>
        <AppButton variant="outline" :to="`/pedidos/${resultado.pedidoId}#order-tickets`">
          Ver ingressos
        </AppButton>
        <AppButton variant="ghost" @click="novaVenda">Nova venda</AppButton>
      </div>
    </BaseCard>

    <form v-else class="space-y-6" novalidate @submit.prevent="revisar">
      <BaseCard class="space-y-5">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
          Evento e tipo da venda
        </h2>

        <FormField label="Evento" required :error="erros.eventoId">
          <BaseSelect v-model="form.eventoId" :options="eventoOptions" />
        </FormField>

        <p v-if="eventos.length === 0" class="text-sm text-zinc-500">
          Nenhum evento elegível para venda manual no momento.
        </p>

        <FormField label="Tipo da venda" required :error="erros.tipo">
          <BaseSelect v-model="form.tipo" :options="tipoOptions" />
        </FormField>

        <template v-if="eventoSelecionado && form.tipo === 'LOTE'">
          <FormField
            label="Lote"
            required
            :error="erros.loteId"
            :hint="
              loteAtual
                ? `${disponibilidadeLote} disponível(is) • ${formatMoeda(loteAtual.preco)}`
                : undefined
            "
          >
            <BaseSelect v-model="form.loteId" :options="loteOptions" />
          </FormField>

          <p v-if="lotesAtivos.length === 0" class="text-sm text-amber-300">
            Este evento não possui lote ativo. Use o tipo "Valor especial" para vender sem lote.
          </p>
        </template>

        <p
          v-if="eventoSelecionado && form.tipo === 'AVULSO'"
          class="rounded-lg border border-amber-400/30 bg-amber-400/5 p-3 text-sm text-amber-200"
        >
          Venda sem lote. Disponibilidade global do evento:
          {{ disponibilidadeEvento }} ingresso(s).
        </p>
      </BaseCard>

      <BaseCard class="space-y-5">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Comprador</h2>

        <FormField label="Nome do comprador" required :error="erros.compradorNome">
          <BaseInput v-model="form.compradorNome" placeholder="Ex.: Maria Silva" />
        </FormField>

        <FormField label="Telefone (opcional)">
          <BaseInput v-model="form.compradorTelefone" placeholder="(11) 99999-0000" />
        </FormField>

        <FormField label="E-mail (opcional)">
          <BaseInput v-model="form.compradorEmail" type="email" placeholder="email@exemplo.com" />
        </FormField>
      </BaseCard>

      <BaseCard class="space-y-5">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
          Ingressos e participantes
        </h2>

        <FormField label="Quantidade" required :error="erros.quantidade">
          <BaseSelect v-model="quantidadeSelecionada" :options="quantidadeOptions" />
        </FormField>

        <div class="space-y-3">
          <FormField
            v-for="(_, indice) in form.participantes"
            :key="indice"
            :label="`Participante ${indice + 1}`"
            :error="indice === 0 ? erros.participantes : undefined"
          >
            <BaseInput
              v-model="form.participantes[indice]"
              :placeholder="`Nome do participante ${indice + 1}`"
            />
          </FormField>
        </div>
      </BaseCard>

      <BaseCard class="space-y-5">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Valores</h2>

        <FormField
          v-if="form.tipo === 'LOTE'"
          label="Valor unitário (do lote)"
          hint="Definido pelo lote; não editável."
        >
          <BaseInput :model-value="formatMoeda(precoUnitario)" disabled />
        </FormField>

        <FormField v-else label="Valor unitário" required :error="erros.valorUnitario">
          <BaseInput
            v-model="form.valorUnitario"
            type="text"
            prefix="R$"
            placeholder="0,00"
          />
        </FormField>
      </BaseCard>

      <BaseCard class="space-y-3">
        <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Resumo</h2>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-zinc-500">Evento</span>
          <span class="text-zinc-200">{{ eventoSelecionado?.nome ?? '—' }}</span>
        </div>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-zinc-500">Tipo</span>
          <span class="text-zinc-200">{{ rotuloTipo(form.tipo) }}</span>
        </div>
        <div
          v-if="form.tipo === 'LOTE' && loteAtual"
          class="flex items-center justify-between gap-3 text-sm"
        >
          <span class="text-zinc-500">Lote</span>
          <span class="text-zinc-200">{{ loteAtual.nome }}</span>
        </div>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-zinc-500">Quantidade</span>
          <span class="text-zinc-200">{{ form.quantidade }}</span>
        </div>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-zinc-500">Valor unitário</span>
          <span class="text-zinc-200">{{ formatMoeda(precoUnitario) }}</span>
        </div>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-zinc-500">Forma de pagamento</span>
          <span class="text-zinc-200">Dinheiro</span>
        </div>
        <div
          class="flex items-center justify-between gap-3 border-t border-zinc-800 pt-3 text-base"
        >
          <span class="font-medium text-zinc-300">Total</span>
          <span class="font-bold text-amber-400">{{ formatMoeda(total) }}</span>
        </div>
      </BaseCard>

      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" to="/pedidos">Cancelar</AppButton>
        <AppButton variant="primary" type="submit" :disabled="!eventoSelecionado">
          Confirmar venda
        </AppButton>
      </div>
    </form>

    <ConfirmDialog
      :open="confirmarAberto"
      title="Confirmar venda em dinheiro?"
      :description="`Confirmar venda em dinheiro no valor de ${formatMoeda(total)}?`"
      confirm-label="Confirmar venda"
      :loading="enviando"
      @confirm="confirmarVenda"
      @cancel="confirmarAberto = false"
    />
  </div>
</template>
