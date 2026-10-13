<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'

import BaseCard from '~/components/BaseCard.vue'
import { definirTaxaEvento, obterTaxaEvento } from '~/services/admin/mercadoPago'
import { formatMoeda } from '~/utils/format'

const props = defineProps<{ eventoId: string }>()

const carregando = ref(true)
const salvando = ref(false)
const taxaRepassada = ref(true)
const taxaServico = ref(0)

async function carregar() {
  carregando.value = true
  try {
    const taxa = await obterTaxaEvento(props.eventoId)
    taxaRepassada.value = taxa.taxaRepassada
    taxaServico.value = taxa.taxaServico
  } catch {
    // o formulario principal ja mostra o erro de carregamento
  } finally {
    carregando.value = false
  }
}

async function escolher(repassar: boolean) {
  if (salvando.value || repassar === taxaRepassada.value) return
  salvando.value = true
  try {
    await definirTaxaEvento(props.eventoId, repassar)
    taxaRepassada.value = repassar
    toast.success('Taxa de serviço atualizada.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar a taxa.')
  } finally {
    salvando.value = false
  }
}

const opcao =
  'flex-1 rounded-xl border px-4 py-3 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50'

onMounted(() => void carregar())
</script>

<template>
  <BaseCard class="mx-auto w-full max-w-5xl">
    <h2 class="text-sm font-semibold text-white">Taxa de serviço</h2>
    <p class="mt-1 text-xs text-zinc-500">
      Taxa da plataforma: {{ formatMoeda(taxaServico) }} por ingresso vendido online. Vendas em
      dinheiro não têm taxa. A mudança vale para os próximos pedidos.
    </p>

    <div v-if="carregando" class="mt-4 h-16 animate-pulse rounded-xl bg-zinc-800" />

    <div v-else class="mt-4 flex flex-col gap-3 sm:flex-row">
      <button
        type="button"
        :disabled="salvando"
        :class="[opcao, taxaRepassada ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 hover:border-zinc-500']"
        @click="escolher(true)"
      >
        <p class="text-sm font-semibold text-white">Repassar ao comprador</p>
        <p class="mt-1 text-xs text-zinc-400">
          O comprador paga o ingresso + {{ formatMoeda(taxaServico) }}. Você recebe o valor cheio do ingresso.
        </p>
      </button>
      <button
        type="button"
        :disabled="salvando"
        :class="[opcao, !taxaRepassada ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 hover:border-zinc-500']"
        @click="escolher(false)"
      >
        <p class="text-sm font-semibold text-white">Absorver a taxa</p>
        <p class="mt-1 text-xs text-zinc-400">
          O comprador paga só o ingresso. A taxa é descontada do valor que você recebe.
        </p>
      </button>
    </div>
  </BaseCard>
</template>
