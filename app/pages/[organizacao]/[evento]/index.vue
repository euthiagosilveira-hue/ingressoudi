<script setup lang="ts">
import { computed, watch } from 'vue'

import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import PublicEventPage from '~/components/public/eventos/PublicEventPage.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { obterEventoPublicoOrganizacao, obterOrganizacaoPublica } from '~/services/public/catalogo'
import { tituloPublico } from '~/utils/marca'

const route = useRoute()
const orgSlug = computed(() => String(route.params.organizacao ?? '').toLowerCase())
const eventoSlug = computed(() => String(route.params.evento ?? '').toLowerCase())

const { data, pending, error, refresh } = await useAsyncData(
  () => `evento-publico-${orgSlug.value}-${eventoSlug.value}`,
  async () => {
    const [evento, organizacao] = await Promise.all([
      obterEventoPublicoOrganizacao(orgSlug.value, eventoSlug.value),
      obterOrganizacaoPublica(orgSlug.value)
    ])
    return { evento, organizacao }
  },
  { watch: [orgSlug, eventoSlug] }
)

const evento = computed(() => data.value?.evento ?? null)
const organizacao = computed(() => data.value?.organizacao ?? null)

const { definir } = useOrganizacaoPublica()
watch(organizacao, (valor) => definir(valor), { immediate: true })

useSeoMeta({
  title: () => tituloPublico(evento.value?.nome ?? 'Evento', organizacao.value?.nome),
  description: () => (evento.value ? evento.value.descricao.slice(0, 155) : 'Evento não encontrado.')
})
</script>

<template>
  <PublicCatalogLoading v-if="pending" />

  <PublicCatalogError v-else-if="error" @retry="refresh" />

  <template v-else>
    <PublicEventPage v-if="evento" :evento="evento" />
    <PublicEventNotFound v-else />
  </template>
</template>
