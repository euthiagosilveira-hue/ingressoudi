<script setup lang="ts">
import { computed, watch } from 'vue'

import CheckoutPage from '~/components/public/checkout/CheckoutPage.vue'
import CheckoutUnavailable from '~/components/public/checkout/CheckoutUnavailable.vue'
import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { obterEventoPublicoOrganizacao } from '~/services/public/catalogo'
import { tituloPublico } from '~/utils/marca'

const route = useRoute()
const orgSlug = computed(() => String(route.params.organizacao ?? '').toLowerCase())
const eventoSlug = computed(() => String(route.params.evento ?? '').toLowerCase())

const { data, pending, error, refresh } = await useAsyncData(
  () => `checkout-evento-${orgSlug.value}-${eventoSlug.value}`,
  () => obterEventoPublicoOrganizacao(orgSlug.value, eventoSlug.value),
  { watch: [orgSlug, eventoSlug] }
)

const evento = computed(() => data.value ?? null)

const { definir } = useOrganizacaoPublica()
watch(
  evento,
  (valor) => {
    if (valor) {
      definir({ slug: valor.organizacaoSlug, nome: valor.organizacaoNome, logoUrl: valor.organizacaoLogoUrl })
    }
  },
  { immediate: true }
)

const podeComprar = computed(() => {
  const atual = evento.value
  if (!atual || atual.situacaoVenda !== 'DISPONIVEL') return false
  if (!atual.loteId || atual.preco === null) return false
  if (typeof atual.disponiveis === 'number' && atual.disponiveis <= 0) return false
  return true
})

useSeoMeta({
  title: () => tituloPublico(evento.value ? `Checkout — ${evento.value.nome}` : 'Checkout', evento.value?.organizacaoNome)
})
</script>

<template>
  <PublicCatalogLoading v-if="pending" />

  <PublicCatalogError v-else-if="error" @retry="refresh" />

  <template v-else>
    <CheckoutPage v-if="evento && podeComprar" :evento="evento" origem="SUPABASE" />
    <CheckoutUnavailable v-else-if="evento" :evento="evento" />
    <PublicEventNotFound v-else />
  </template>
</template>
