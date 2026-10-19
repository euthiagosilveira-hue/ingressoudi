<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { ChevronRightIcon, ExclamationTriangleIcon, TicketIcon, XMarkIcon } from '@heroicons/vue/24/outline'

import { useIngressosSalvos } from '~/composables/useIngressosSalvos'
import { recuperarIngressos } from '~/services/public/recuperacao'
import { formatDataHora } from '~/utils/format'
import { eventoJaPassou } from '~/utils/ingressosSalvos'
import { normalizarCodigoPedido, normalizarTelefone } from '~/utils/publicIngressos'
import { rotaIngressosPedido } from '~/utils/rotasPublicas'

const { pedidos, remover } = useIngressosSalvos()
const temSalvos = computed(() => pedidos.value.length > 0)

const form = reactive({ codigo: '', telefone: '' })
const carregando = ref(false)
const erro = ref('')

const podeEnviar = computed(
  () => normalizarCodigoPedido(form.codigo).length >= 3 && normalizarTelefone(form.telefone).length >= 10
)

async function enviar() {
  erro.value = ''
  if (!podeEnviar.value) {
    erro.value = 'Informe o código do pedido e o telefone usado na compra.'
    return
  }

  carregando.value = true
  try {
    const resultado = await recuperarIngressos({
      codigo: form.codigo,
      telefone: form.telefone
    })
    if (!resultado.ok || !resultado.token) {
      erro.value = 'Não foi possível localizar uma compra com os dados informados.'
      return
    }
    await navigateTo({ path: '/meus-ingressos', query: { recovery: resultado.token } })
  } catch {
    erro.value = 'Não foi possível recuperar agora. Tente novamente.'
  } finally {
    carregando.value = false
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-zinc-950 px-4 py-10 text-white">
    <section class="w-full max-w-md space-y-6 rounded-2xl border border-zinc-800 bg-zinc-900 p-6 sm:p-8">
      <header class="space-y-3 text-center">
        <span class="mx-auto flex h-12 w-12 items-center justify-center rounded-full border border-zinc-700 bg-zinc-950">
          <TicketIcon class="h-6 w-6 text-amber-400" />
        </span>
        <h1 class="text-lg font-bold uppercase tracking-wide text-amber-400">Meus ingressos</h1>
        <p v-if="!temSalvos" class="text-sm text-zinc-400">
          Informe o código do pedido e o telefone usado na compra para acessar seus ingressos.
        </p>
      </header>

      <div v-if="temSalvos" class="space-y-3">
        <p class="text-xs font-semibold uppercase tracking-wide text-zinc-400">Salvos neste aparelho</p>
        <ul class="space-y-2">
          <li
            v-for="p in pedidos"
            :key="p.pedidoId"
            class="flex items-stretch gap-2"
            :class="eventoJaPassou(p) ? 'opacity-60' : ''"
          >
            <NuxtLink
              :to="rotaIngressosPedido(p.organizacaoSlug, p.eventoSlug, p.checkoutToken)"
              class="flex min-w-0 flex-1 items-center gap-3 rounded-xl border border-zinc-700 bg-zinc-950 px-4 py-3 transition-colors hover:border-amber-400/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
            >
              <TicketIcon class="h-5 w-5 shrink-0 text-amber-400" />
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-semibold text-white">{{ p.eventoNome }}</span>
                <span class="block truncate text-xs text-zinc-500">
                  <template v-if="p.eventoInicioEm">{{ formatDataHora(p.eventoInicioEm) }} · </template>
                  <template v-if="p.quantidade">{{ p.quantidade }} ingresso{{ p.quantidade === 1 ? '' : 's' }} · </template>
                  Pedido {{ p.codigoPedido }}
                </span>
              </span>
              <ChevronRightIcon class="h-4 w-4 shrink-0 text-zinc-500" />
            </NuxtLink>
            <button
              type="button"
              :aria-label="`Remover ${p.eventoNome} deste aparelho`"
              class="flex w-10 shrink-0 items-center justify-center rounded-xl border border-zinc-800 text-zinc-500 transition-colors hover:border-zinc-600 hover:text-zinc-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
              @click="remover(p.pedidoId)"
            >
              <XMarkIcon class="h-4 w-4" />
            </button>
          </li>
        </ul>
        <div class="border-t border-zinc-800 pt-5">
          <p class="text-sm font-semibold text-zinc-200">Comprou em outro aparelho?</p>
          <p class="mt-1 text-xs text-zinc-500">
            Informe o código do pedido e o telefone usado na compra.
          </p>
        </div>
      </div>

      <p
        v-if="erro"
        role="alert"
        class="flex items-start gap-2 rounded-xl border border-red-500/40 bg-red-500/5 p-3 text-sm text-red-300"
      >
        <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
        <span>{{ erro }}</span>
      </p>

      <form class="space-y-4" @submit.prevent="enviar">
        <div class="space-y-1.5">
          <label for="codigo" class="block text-xs font-semibold uppercase tracking-wide text-zinc-400">
            Código do pedido
          </label>
          <input
            id="codigo"
            v-model="form.codigo"
            type="text"
            autocomplete="off"
            class="w-full rounded-xl border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm uppercase text-zinc-100 placeholder:text-zinc-600 focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
            placeholder="IU100123"
          />
        </div>

        <div class="space-y-1.5">
          <label for="telefone" class="block text-xs font-semibold uppercase tracking-wide text-zinc-400">
            Telefone usado na compra
          </label>
          <input
            id="telefone"
            v-model="form.telefone"
            type="tel"
            autocomplete="tel"
            class="w-full rounded-xl border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm text-zinc-100 placeholder:text-zinc-600 focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
            placeholder="(11) 99999-0000"
          />
        </div>

        <button
          type="submit"
          :disabled="carregando"
          class="flex w-full items-center justify-center rounded-xl bg-amber-400 px-6 py-4 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors duration-150 hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/60 disabled:pointer-events-none disabled:opacity-50"
        >
          {{ carregando ? 'Recuperando...' : 'Recuperar ingressos' }}
        </button>
      </form>

      <NuxtLink
        to="/"
        class="block text-center text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
      >
        Voltar ao início
      </NuxtLink>
    </section>
  </main>
</template>
