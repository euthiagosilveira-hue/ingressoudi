<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { toast } from 'vue3-toastify'

import BaseCard from '~/components/BaseCard.vue'
import { definirMeiaEntradaEvento, obterMeiaEntradaEvento } from '~/services/admin/eventos'

const props = defineProps<{ eventoId: string }>()

const carregando = ref(true)
const salvando = ref(false)
const ativa = ref(false)

async function carregar() {
  carregando.value = true
  try {
    ativa.value = await obterMeiaEntradaEvento(props.eventoId)
  } catch {
    // a pagina principal ja mostra o erro de carregamento
  } finally {
    carregando.value = false
  }
}

async function escolher(valor: boolean) {
  if (salvando.value || valor === ativa.value) return
  salvando.value = true
  try {
    await definirMeiaEntradaEvento(props.eventoId, valor)
    ativa.value = valor
    toast.success(valor ? 'Meia-entrada ativada.' : 'Meia-entrada desativada.')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Não foi possível salvar a meia-entrada.')
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
    <h2 class="text-sm font-semibold text-white">Meia-entrada</h2>
    <p class="mt-1 text-xs text-zinc-500">
      Com a meia-entrada ativa, o comprador escolhe inteira ou meia em cada ingresso. A meia custa
      50% do preço do lote e a taxa de serviço não muda. Quem compra meia apresenta o documento na
      entrada. A mudança vale para os próximos pedidos.
    </p>

    <div v-if="carregando" class="mt-4 h-16 animate-pulse rounded-xl bg-zinc-800" />

    <div v-else class="mt-4 flex flex-col gap-3 sm:flex-row">
      <button
        type="button"
        :disabled="salvando"
        :class="[opcao, ativa ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 hover:border-zinc-500']"
        @click="escolher(true)"
      >
        <p class="text-sm font-semibold text-white">Ativar meia-entrada</p>
        <p class="mt-1 text-xs text-zinc-400">
          Ex.: lote de R$ 50,00 vende inteira a R$ 50,00 e meia a R$ 25,00.
        </p>
      </button>
      <button
        type="button"
        :disabled="salvando"
        :class="[opcao, !ativa ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 hover:border-zinc-500']"
        @click="escolher(false)"
      >
        <p class="text-sm font-semibold text-white">Sem meia-entrada</p>
        <p class="mt-1 text-xs text-zinc-400">Todos os ingressos são vendidos pelo preço do lote.</p>
      </button>
    </div>
  </BaseCard>
</template>
