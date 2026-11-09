<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { MagnifyingGlassIcon, QrCodeIcon, TicketIcon, BuildingStorefrontIcon, XMarkIcon } from '@heroicons/vue/24/outline'

import AjudaArtigoCard from '~/components/ajuda/AjudaArtigoCard.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { CATEGORIAS_AJUDA, artigosDaCategoria, buscarArtigosAjuda, caminhoArtigoAjuda } from '~/utils/ajuda'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `Central de ajuda | ${PLATAFORMA_NOME}`,
  description: `Passo a passo com imagens para usar o ${PLATAFORMA_NOME}: cadastro, Mercado Pago, eventos, portaria e compra de ingressos.`
})

const route = useRoute()
const router = useRouter()
const busca = ref(String(route.query.q ?? ''))

// Mantem a busca na URL para poder compartilhar o resultado.
watch(busca, (valor) => {
  const q = valor.trim()
  router.replace({ query: q ? { q } : {} })
})

const resultados = computed(() => buscarArtigosAjuda(busca.value))
const buscando = computed(() => busca.value.trim().length >= 2)

const categorias = computed(() =>
  CATEGORIAS_AJUDA.map((categoria) => ({ ...categoria, artigos: artigosDaCategoria(categoria.id) }))
)

const atalhos = [
  { icone: BuildingStorefrontIcon, titulo: 'Sou produtor', texto: 'Comece pelo cadastro', to: caminhoArtigoAjuda('criar-conta') },
  { icone: QrCodeIcon, titulo: 'Trabalho na portaria', texto: 'Validar ingressos', to: caminhoArtigoAjuda('validar-ingressos') },
  { icone: TicketIcon, titulo: 'Comprei um ingresso', texto: 'Onde achar meu ingresso', to: caminhoArtigoAjuda('encontrar-ingressos') }
]
</script>

<template>
  <div class="mx-auto w-full max-w-4xl px-4 py-10 sm:px-6 sm:py-14">
    <p class="text-xs font-semibold uppercase tracking-[0.2em] text-amber-400">{{ PLATAFORMA_NOME }}</p>
    <h1 class="mt-3 text-3xl font-bold text-white sm:text-4xl">Central de ajuda</h1>
    <p class="mt-2 text-zinc-400">Passo a passo com as telas do sistema, do cadastro ao dia do evento.</p>

    <label class="relative mt-6 block">
      <span class="sr-only">Buscar na central de ajuda</span>
      <MagnifyingGlassIcon class="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-zinc-500" />
      <input
        v-model="busca"
        type="text"
        enterkeyhint="search"
        autocomplete="off"
        placeholder="Ex.: como convidar o porteiro, Pix não confirmou, meia-entrada"
        class="w-full rounded-xl border border-zinc-700 bg-zinc-900 py-3.5 pl-12 pr-11 text-base text-white placeholder:text-zinc-500 focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
      />
      <button
        v-if="busca"
        type="button"
        aria-label="Limpar busca"
        class="absolute right-3 top-1/2 -translate-y-1/2 rounded-md p-1 text-zinc-500 hover:text-white"
        @click="busca = ''"
      >
        <XMarkIcon class="h-5 w-5" />
      </button>
    </label>

    <section v-if="buscando" class="mt-8" aria-live="polite">
      <p class="text-sm text-zinc-400">
        {{ resultados.length === 1 ? '1 artigo encontrado' : `${resultados.length} artigos encontrados` }}
      </p>
      <div v-if="resultados.length" class="mt-3 space-y-2">
        <AjudaArtigoCard v-for="artigo in resultados" :key="artigo.slug" :artigo="artigo" />
      </div>
      <p v-else class="mt-3 rounded-xl border border-zinc-800 bg-zinc-900/70 p-4 text-sm text-zinc-300">
        Nada encontrado. Tente outras palavras, como "lote", "convite" ou "Pix".
      </p>
    </section>

    <template v-else>
      <div class="mt-8 grid gap-3 sm:grid-cols-3">
        <NuxtLink
          v-for="atalho in atalhos"
          :key="atalho.titulo"
          :to="atalho.to"
          class="flex items-center gap-3 rounded-xl border border-zinc-800 bg-zinc-900/70 p-4 transition-colors hover:border-amber-400/40"
        >
          <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-amber-400/30 bg-amber-400/10 text-amber-400">
            <component :is="atalho.icone" class="h-5 w-5" />
          </span>
          <span>
            <span class="block text-sm font-semibold text-white">{{ atalho.titulo }}</span>
            <span class="block text-xs text-zinc-400">{{ atalho.texto }}</span>
          </span>
        </NuxtLink>
      </div>

      <section v-for="categoria in categorias" :key="categoria.id" class="mt-10">
        <h2 class="text-lg font-semibold text-white">{{ categoria.titulo }}</h2>
        <p class="text-sm text-zinc-500">{{ categoria.descricao }}</p>
        <div class="mt-3 space-y-2">
          <AjudaArtigoCard v-for="artigo in categoria.artigos" :key="artigo.slug" :artigo="artigo" />
        </div>
      </section>
    </template>
  </div>
</template>
