<script setup lang="ts">
import { computed } from 'vue'

import PublicEventAvailability from '~/components/public/eventos/PublicEventAvailability.vue'
import PublicEventUnavailable from '~/components/public/eventos/PublicEventUnavailable.vue'
import { formatMoeda } from '~/utils/format'
import { precoMeia } from '~/utils/meiaEntrada'
import { rotaCheckout } from '~/utils/rotasPublicas'
import { eventoTemSetores, rotaCheckoutSetor } from '~/utils/setores'
import type { PublicEventDetail, PublicVendaSituacao } from '~/types/publicEvento'

const props = defineProps<{
  evento: PublicEventDetail
}>()

const temSetores = computed(() => eventoTemSetores(props.evento))

// Com setores, cada setor mostra o proprio "esgotado"; o cartao inteiro so
// fica bloqueado quando a venda do evento todo nao esta aberta.
const situacaoBloqueada = computed<Exclude<PublicVendaSituacao, 'DISPONIVEL'> | null>(() => {
  const situacao = props.evento.situacaoVenda
  if (situacao === 'DISPONIVEL') return null
  if (temSetores.value && situacao === 'ESGOTADO') return null
  return situacao
})

const ROTULO_SETOR: Partial<Record<PublicVendaSituacao, string>> = {
  ESGOTADO: 'Esgotado',
  SEM_LOTE: 'Em breve'
}

function rotuloSetor(situacao: PublicVendaSituacao): string {
  return ROTULO_SETOR[situacao] ?? 'Indisponível'
}
</script>

<template>
  <section class="rounded-2xl border border-zinc-800 bg-zinc-900 p-5 sm:p-6 lg:sticky lg:top-24">
    <template v-if="situacaoBloqueada">
      <PublicEventUnavailable :situacao="situacaoBloqueada" />
    </template>

    <template v-else-if="temSetores">
      <p class="text-xs uppercase tracking-wide text-zinc-500">Escolha o setor</p>

      <ul class="mt-3 space-y-3">
        <li
          v-for="setor in props.evento.setores"
          :key="setor.setorId"
          class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-base font-bold text-white">{{ setor.nome }}</p>
              <p v-if="setor.loteNome" class="text-xs text-zinc-500">{{ setor.loteNome }}</p>
            </div>
            <div v-if="setor.situacaoVenda === 'DISPONIVEL'" class="text-right">
              <p class="text-xl font-bold" style="color: var(--cor-casa)">{{ formatMoeda(setor.preco ?? 0) }}</p>
              <p v-if="props.evento.meiaEntradaAtiva" class="text-xs text-zinc-500">
                Meia {{ formatMoeda(precoMeia(setor.preco)) }}
              </p>
            </div>
            <span
              v-else
              class="shrink-0 rounded-full border border-zinc-700 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-zinc-400"
            >
              {{ rotuloSetor(setor.situacaoVenda) }}
            </span>
          </div>

          <NuxtLink
            v-if="setor.situacaoVenda === 'DISPONIVEL'"
            :to="rotaCheckoutSetor(props.evento.organizacaoSlug, props.evento.slug, setor.setorId)"
            class="mt-3 flex w-full items-center justify-center rounded-xl px-4 py-3 text-sm font-bold uppercase tracking-wide transition-opacity duration-150 hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
            style="background: var(--cor-casa); color: var(--cor-casa-texto)"
          >
            Comprar {{ setor.nome }}
          </NuxtLink>
        </li>
      </ul>

      <p class="mt-3 text-xs text-zinc-500">
        Preço por ingresso<template v-if="(props.evento.taxaServico ?? 0) > 0">
          + {{ formatMoeda(props.evento.taxaServico ?? 0) }} de taxa de serviço</template>.
      </p>
    </template>

    <template v-else>
      <p class="text-xs uppercase tracking-wide text-zinc-500">Lote atual</p>
      <p class="text-sm font-semibold text-white">{{ props.evento.loteNome ?? 'Lote' }}</p>

      <div class="mt-4">
        <div v-if="props.evento.meiaEntradaAtiva" class="flex flex-wrap items-end gap-x-6 gap-y-2">
          <div>
            <p class="text-xs text-zinc-500">Inteira</p>
            <p class="text-3xl font-bold" style="color: var(--cor-casa)">
              {{ formatMoeda(props.evento.preco ?? 0) }}
            </p>
          </div>
          <div>
            <p class="text-xs text-zinc-500">Meia-entrada</p>
            <p class="text-3xl font-bold" style="color: var(--cor-casa)">
              {{ formatMoeda(precoMeia(props.evento.preco)) }}
            </p>
          </div>
        </div>
        <p v-else class="text-3xl font-bold" style="color: var(--cor-casa)">
          {{ formatMoeda(props.evento.preco ?? 0) }}
        </p>
        <p class="text-xs text-zinc-500">
          por ingresso<template v-if="(props.evento.taxaServico ?? 0) > 0">
            + {{ formatMoeda(props.evento.taxaServico ?? 0) }} de taxa de serviço</template>
        </p>
      </div>

      <div class="mt-3">
        <PublicEventAvailability :disponiveis="props.evento.disponiveis" />
      </div>

      <NuxtLink
        :to="rotaCheckout(props.evento.organizacaoSlug, props.evento.slug)"
        class="mt-6 flex w-full items-center justify-center rounded-xl px-6 py-4 text-sm font-bold uppercase tracking-wide transition-opacity duration-150 hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
        style="background: var(--cor-casa); color: var(--cor-casa-texto)"
      >
        Comprar ingresso
      </NuxtLink>
    </template>
  </section>
</template>
