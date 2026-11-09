<script setup lang="ts">
import { computed } from 'vue'
import { ArrowLeftIcon, ChevronDownIcon, InformationCircleIcon } from '@heroicons/vue/24/outline'

import AjudaArtigoCard from '~/components/ajuda/AjudaArtigoCard.vue'
import AjudaTexto from '~/components/ajuda/AjudaTexto.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import {
  CATEGORIAS_AJUDA,
  ROTULO_PUBLICO,
  artigosRelacionados,
  imagemAjuda,
  obterArtigoAjuda
} from '~/utils/ajuda'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: 'public-layout'
})

useOrganizacaoPublica().limpar()

const route = useRoute()
const slug = computed(() => String(route.params.slug ?? ''))
const artigo = computed(() => obterArtigoAjuda(slug.value))
const categoria = computed(() => CATEGORIAS_AJUDA.find((c) => c.id === artigo.value?.categoria) ?? null)
const relacionados = computed(() => artigosRelacionados(slug.value))

useSeoMeta({
  title: () => (artigo.value ? `${artigo.value.titulo} | Ajuda ${PLATAFORMA_NOME}` : `Central de ajuda | ${PLATAFORMA_NOME}`),
  description: () => artigo.value?.resumo ?? `Central de ajuda do ${PLATAFORMA_NOME}.`
})
</script>

<template>
  <div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 sm:py-12">
    <NuxtLink to="/ajuda" class="inline-flex items-center gap-1.5 text-sm text-zinc-400 hover:text-amber-400">
      <ArrowLeftIcon class="h-4 w-4" />
      Central de ajuda
    </NuxtLink>

    <div v-if="!artigo" class="mt-8 rounded-xl border border-zinc-800 bg-zinc-900/70 p-6">
      <h1 class="text-xl font-semibold text-white">Artigo não encontrado</h1>
      <p class="mt-2 text-sm text-zinc-400">Volte para a central de ajuda e use a busca.</p>
    </div>

    <article v-else>
      <p v-if="categoria" class="mt-6 text-xs font-semibold uppercase tracking-[0.2em] text-amber-400">
        {{ categoria.titulo }}
      </p>
      <h1 class="mt-2 text-2xl font-bold text-white sm:text-3xl">{{ artigo.titulo }}</h1>
      <p class="mt-2 text-zinc-400">{{ artigo.resumo }}</p>
      <div class="mt-3 flex flex-wrap gap-2">
        <span
          v-for="p in artigo.publico"
          :key="p"
          class="rounded-full border border-zinc-700 px-2.5 py-0.5 text-xs text-zinc-300"
        >
          {{ ROTULO_PUBLICO[p] }}
        </span>
      </div>

      <div v-if="artigo.antes" class="mt-6 flex gap-3 rounded-xl border border-amber-400/30 bg-amber-400/5 p-4 text-sm text-zinc-200">
        <InformationCircleIcon class="h-5 w-5 shrink-0 text-amber-400" />
        <p><span class="font-semibold text-amber-300">Antes de começar:</span> {{ artigo.antes }}</p>
      </div>

      <ol class="mt-8 space-y-10">
        <li v-for="(passo, i) in artigo.passos" :key="i" class="flex gap-4">
          <span
            class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-amber-400 text-sm font-bold text-zinc-950"
            aria-hidden="true"
          >
            {{ i + 1 }}
          </span>
          <div class="min-w-0 flex-1 pt-1">
            <p class="leading-relaxed text-zinc-300"><AjudaTexto :texto="passo.texto" /></p>
            <a
              v-if="passo.imagem"
              :href="imagemAjuda(passo.imagem)"
              target="_blank"
              rel="noopener"
              class="mt-4 block overflow-hidden rounded-xl border border-zinc-800 bg-black transition-colors hover:border-amber-400/40"
              :class="passo.celular ? 'max-w-sm' : ''"
              :aria-label="`Abrir imagem ampliada: ${passo.alt ?? ''}`"
            >
              <img :src="imagemAjuda(passo.imagem)" :alt="passo.alt ?? ''" loading="lazy" decoding="async" class="block h-auto w-full" />
            </a>
          </div>
        </li>
      </ol>

      <section v-if="artigo.problemas?.length" class="mt-12">
        <h2 class="text-lg font-semibold text-white">Dúvidas comuns</h2>
        <div class="mt-3 space-y-2">
          <details
            v-for="item in artigo.problemas"
            :key="item.pergunta"
            class="group rounded-xl border border-zinc-800 bg-zinc-900/70 px-4 py-3"
          >
            <summary class="flex cursor-pointer list-none items-center justify-between gap-3 font-medium text-white">
              {{ item.pergunta }}
              <ChevronDownIcon class="h-4 w-4 shrink-0 text-zinc-500 transition-transform group-open:rotate-180" />
            </summary>
            <p class="mt-2 text-sm text-zinc-400">{{ item.resposta }}</p>
          </details>
        </div>
      </section>

      <section v-if="relacionados.length" class="mt-12">
        <h2 class="text-lg font-semibold text-white">Veja também</h2>
        <div class="mt-3 space-y-2">
          <AjudaArtigoCard v-for="item in relacionados" :key="item.slug" :artigo="item" />
        </div>
      </section>
    </article>
  </div>
</template>
