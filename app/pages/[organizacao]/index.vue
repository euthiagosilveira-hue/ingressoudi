<script setup lang="ts">
import { computed, watch } from 'vue'
import { toast } from 'vue3-toastify'
import { BuildingStorefrontIcon, CalendarDaysIcon, MapPinIcon, ShareIcon } from '@heroicons/vue/24/outline'

import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventStatusBadge from '~/components/public/eventos/PublicEventStatusBadge.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { listarEventosPublicosOrganizacao, obterOrganizacaoPublica } from '~/services/public/catalogo'
import { formatData, formatHora, formatMoeda } from '~/utils/format'
import { copiarTexto } from '~/utils/linkEvento'
import { iniciais, tituloPublico } from '~/utils/marca'
import { rotaEvento } from '~/utils/rotasPublicas'
import { agruparEventosPorMes, seloSituacaoVitrine, textoQuantidadeEventos, urlVitrine } from '~/utils/vitrine'

const route = useRoute()
const orgSlug = computed(() => String(route.params.organizacao ?? '').toLowerCase())

const { data, pending, error, refresh } = await useAsyncData(
  () => `organizacao-publica-${orgSlug.value}`,
  async () => {
    // Em paralelo: um segundo useSupabaseClient depois de um await perde o
    // contexto do Nuxt no servidor (NUXT_E1001) e a pagina abria com erro.
    const [organizacao, eventos] = await Promise.all([
      obterOrganizacaoPublica(orgSlug.value),
      listarEventosPublicosOrganizacao(orgSlug.value)
    ])
    if (!organizacao) return { organizacao: null, eventos: [] }
    return { organizacao, eventos }
  },
  { watch: [orgSlug] }
)

const organizacao = computed(() => data.value?.organizacao ?? null)
const eventos = computed(() => data.value?.eventos ?? [])
const grupos = computed(() => agruparEventosPorMes(eventos.value))

const config = useRuntimeConfig()

/** Web Share no celular; no computador (ou se falhar) copia o link. */
async function compartilhar() {
  if (!organizacao.value) return
  const origem = typeof window !== 'undefined' ? window.location.origin : String(config.public.siteUrl || '')
  const url = urlVitrine(origem, organizacao.value.slug)
  const nav = typeof navigator !== 'undefined' ? navigator : undefined
  if (nav && typeof nav.share === 'function') {
    try {
      await nav.share({ title: organizacao.value.nome, text: `Agenda de ${organizacao.value.nome}`, url })
      return
    } catch (e) {
      if ((e as DOMException)?.name === 'AbortError') return
    }
  }
  if (await copiarTexto(url)) toast.success('Link copiado! Agora é só colar onde quiser divulgar.')
  else toast.error(`Não foi possível copiar. Copie manualmente: ${url}`)
}

const { definir } = useOrganizacaoPublica()
watch(organizacao, (valor) => definir(valor), { immediate: true })

useSeoMeta({
  title: () => tituloPublico('Eventos', organizacao.value?.nome),
  description: () =>
    organizacao.value
      ? `Confira a agenda de ${organizacao.value.nome} e garanta seu ingresso.`
      : 'Casa não encontrada.'
})
</script>

<template>
  <PublicCatalogLoading v-if="pending" />

  <PublicCatalogError v-else-if="error" @retry="refresh" />

  <section
    v-else-if="!organizacao"
    class="mx-auto flex max-w-2xl flex-col items-center px-4 py-20 text-center sm:py-28"
  >
    <div class="flex h-16 w-16 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-500">
      <BuildingStorefrontIcon class="h-8 w-8" />
    </div>
    <h1 class="mt-6 text-2xl font-bold text-white">Página não encontrada</h1>
    <p class="mt-2 text-sm text-zinc-400">Confira o endereço digitado.</p>
    <NuxtLink
      to="/"
      class="mt-8 inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-8 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors duration-150 hover:bg-amber-400 hover:text-zinc-950"
    >
      Voltar ao início
    </NuxtLink>
  </section>

  <div v-else class="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 sm:py-12">
    <header class="flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex min-w-0 items-center gap-4">
        <img
          v-if="organizacao.logoUrl"
          :src="organizacao.logoUrl"
          :alt="`Logo de ${organizacao.nome}`"
          class="h-16 w-16 shrink-0 rounded-2xl border border-zinc-800 bg-zinc-900 object-cover sm:h-20 sm:w-20"
        />
        <div
          v-else
          class="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl text-xl font-extrabold sm:h-20 sm:w-20 sm:text-2xl"
          style="background: var(--cor-casa); color: var(--cor-casa-texto)"
          aria-hidden="true"
        >
          {{ iniciais(organizacao.nome) }}
        </div>
        <div class="min-w-0">
          <h1 class="truncate text-2xl font-bold text-white sm:text-3xl">{{ organizacao.nome }}</h1>
          <p class="mt-1 text-sm text-zinc-400">{{ textoQuantidadeEventos(eventos.length) }}</p>
        </div>
      </div>

      <button
        type="button"
        class="inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 self-start rounded-xl border border-zinc-700 px-4 py-2.5 text-sm font-semibold text-zinc-200 transition-colors hover:border-zinc-500 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 sm:self-auto"
        @click="compartilhar"
      >
        <ShareIcon class="h-4 w-4" />
        Compartilhar
      </button>
    </header>

    <p
      v-if="eventos.length === 0"
      class="mt-8 rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-16 text-center text-sm text-zinc-500"
    >
      Nenhum evento disponível no momento. Volte em breve!
    </p>

    <template v-else>
    <section v-for="grupo in grupos" :key="grupo.chave" class="mt-10">
      <h2 class="flex items-center gap-3 text-sm font-bold uppercase tracking-[0.15em] text-zinc-400">
        <span class="h-4 w-1 rounded-full" style="background: var(--cor-casa)" aria-hidden="true" />
        {{ grupo.rotulo }}
      </h2>

      <div class="mt-4 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
        <NuxtLink
          v-for="evento in grupo.eventos"
          :key="evento.slug"
          :to="rotaEvento(organizacao.slug, evento.slug)"
          class="vitrine-card group overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900 transition-colors duration-200"
        >
          <div class="relative aspect-video w-full overflow-hidden bg-zinc-950">
            <img
              v-if="evento.imagemUrl"
              :src="evento.imagemUrl"
              :alt="evento.nome"
              loading="lazy"
              class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
            />
            <div
              v-else
              class="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-800 via-zinc-900 to-black"
            >
              <CalendarDaysIcon class="h-8 w-8" style="color: var(--cor-casa)" />
            </div>
            <div class="absolute left-3 top-3 flex flex-wrap gap-2">
              <PublicEventStatusBadge :status="evento.status" />
              <span
                v-if="seloSituacaoVitrine(evento.situacaoVenda)"
                class="inline-flex items-center rounded-full border border-zinc-600/60 bg-black/70 px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-zinc-200 backdrop-blur-sm"
              >
                {{ seloSituacaoVitrine(evento.situacaoVenda) }}
              </span>
            </div>
          </div>

          <div class="space-y-2 p-4">
            <h3 class="vitrine-card-titulo truncate text-lg font-semibold text-white">
              {{ evento.nome }}
            </h3>
            <p class="text-sm text-zinc-400">
              {{ formatData(evento.inicioEm) }} • {{ formatHora(evento.inicioEm) }}
            </p>
            <p v-if="evento.local" class="flex items-center gap-2 text-sm text-zinc-500">
              <MapPinIcon class="h-4 w-4 shrink-0" />
              <span class="truncate">{{ evento.local }}</span>
            </p>
            <p
              v-if="evento.preco !== null && evento.situacaoVenda === 'DISPONIVEL'"
              class="pt-1 text-sm font-semibold"
              style="color: var(--cor-casa)"
            >
              A partir de {{ formatMoeda(evento.preco) }}
            </p>
          </div>
        </NuxtLink>
      </div>
    </section>
    </template>
  </div>
</template>

<style scoped>
.vitrine-card:hover,
.vitrine-card:focus-visible {
  border-color: color-mix(in srgb, var(--cor-casa) 50%, transparent);
}
.vitrine-card:hover .vitrine-card-titulo {
  color: var(--cor-casa);
}
</style>
