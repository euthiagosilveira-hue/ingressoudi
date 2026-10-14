<script setup lang="ts">
import { computed, watch } from 'vue'
import { BuildingStorefrontIcon, CalendarDaysIcon, MapPinIcon } from '@heroicons/vue/24/outline'

import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventStatusBadge from '~/components/public/eventos/PublicEventStatusBadge.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { listarEventosPublicosOrganizacao, obterOrganizacaoPublica } from '~/services/public/catalogo'
import { formatData, formatHora, formatMoeda } from '~/utils/format'
import { tituloPublico } from '~/utils/marca'
import { rotaEvento } from '~/utils/rotasPublicas'

const route = useRoute()
const orgSlug = computed(() => String(route.params.organizacao ?? '').toLowerCase())

const { data, pending, error, refresh } = await useAsyncData(
  () => `organizacao-publica-${orgSlug.value}`,
  async () => {
    const organizacao = await obterOrganizacaoPublica(orgSlug.value)
    if (!organizacao) return { organizacao: null, eventos: [] }
    const eventos = await listarEventosPublicosOrganizacao(organizacao.slug)
    return { organizacao, eventos }
  },
  { watch: [orgSlug] }
)

const organizacao = computed(() => data.value?.organizacao ?? null)
const eventos = computed(() => data.value?.eventos ?? [])

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
    <h1 class="text-3xl font-bold text-white">{{ organizacao.nome }}</h1>
    <p class="mt-2 text-sm text-zinc-400">Confira a agenda e garanta seu ingresso.</p>

    <p
      v-if="eventos.length === 0"
      class="mt-8 rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 px-6 py-16 text-center text-sm text-zinc-500"
    >
      Nenhum evento disponível no momento.
    </p>

    <div v-else class="mt-8 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <NuxtLink
        v-for="evento in eventos"
        :key="evento.slug"
        :to="rotaEvento(organizacao.slug, evento.slug)"
        class="group overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900 transition-colors duration-200 hover:border-amber-400/40"
      >
        <div class="relative aspect-video w-full overflow-hidden bg-zinc-950">
          <img
            v-if="evento.imagemUrl"
            :src="evento.imagemUrl"
            :alt="evento.nome"
            class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
          />
          <div
            v-else
            class="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-800 via-zinc-900 to-black"
          >
            <CalendarDaysIcon class="h-8 w-8 text-amber-400/80" />
          </div>
          <div class="absolute left-3 top-3">
            <PublicEventStatusBadge :status="evento.status" />
          </div>
        </div>

        <div class="space-y-2 p-4">
          <h2 class="truncate text-lg font-semibold text-white group-hover:text-amber-400">
            {{ evento.nome }}
          </h2>
          <p class="text-sm text-zinc-400">
            {{ formatData(evento.inicioEm) }} • {{ formatHora(evento.inicioEm) }}
          </p>
          <p class="flex items-center gap-2 text-sm text-zinc-500">
            <MapPinIcon class="h-4 w-4 shrink-0" />
            <span class="truncate">{{ evento.local }}</span>
          </p>
          <p v-if="evento.preco !== null" class="pt-1 text-sm font-semibold text-amber-400">
            {{ formatMoeda(evento.preco) }}
          </p>
        </div>
      </NuxtLink>
    </div>
  </div>
</template>
