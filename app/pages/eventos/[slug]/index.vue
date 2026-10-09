<script setup lang="ts">
import { computed } from 'vue'

import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import PublicEventPage from '~/components/public/eventos/PublicEventPage.vue'
import { useCatalogoPublico } from '~/composables/useCatalogoPublico'

const route = useRoute()
const slug = computed(() => String(route.params.slug))

const { obter } = useCatalogoPublico()

const { data, pending, error, refresh } = await useAsyncData(
  () => `evento-publico-${slug.value}`,
  () => obter(slug.value),
  { watch: [slug] }
)

const evento = computed(() => data.value?.evento ?? null)
const fallbackDev = computed(() => import.meta.dev && Boolean(data.value?.fallback))

useSeoMeta({
  title: () => (evento.value ? `${evento.value.nome} | GZ1 Ingresso` : 'Evento | GZ1 Ingresso'),
  description: () =>
    evento.value
      ? evento.value.descricao.slice(0, 155)
      : 'Confira os eventos da Galeria Zero 1.'
})
</script>

<template>
  <PublicCatalogLoading v-if="pending" />

  <PublicCatalogError v-else-if="error" @retry="refresh" />

  <template v-else>
    <p
      v-if="fallbackDev"
      class="mx-auto mt-4 w-full max-w-6xl px-4 text-xs text-amber-300 sm:px-6"
    >
      Modo desenvolvimento: exibindo dados de demonstração.
    </p>

    <PublicEventPage v-if="evento" :evento="evento" />
    <PublicEventNotFound v-else />
  </template>
</template>
