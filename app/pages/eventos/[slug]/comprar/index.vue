<script setup lang="ts">
import { computed } from 'vue'

import CheckoutPage from '~/components/public/checkout/CheckoutPage.vue'
import CheckoutUnavailable from '~/components/public/checkout/CheckoutUnavailable.vue'
import PublicCatalogError from '~/components/public/PublicCatalogError.vue'
import PublicCatalogLoading from '~/components/public/PublicCatalogLoading.vue'
import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import { useCatalogoPublico } from '~/composables/useCatalogoPublico'
import type { EventoOrigem } from '~/types/checkout'

const route = useRoute()
const slug = computed(() => String(route.params.slug))

const { obter } = useCatalogoPublico()

const { data, pending, error, refresh } = await useAsyncData(
  () => `checkout-evento-${slug.value}`,
  () => obter(slug.value),
  { watch: [slug] }
)

const evento = computed(() => data.value?.evento ?? null)
const origem = computed<EventoOrigem>(() => (data.value?.fallback ? 'MOCK' : 'SUPABASE'))
const avisoDev = computed(() => import.meta.dev && origem.value === 'MOCK')

const podeComprar = computed(() => {
  const atual = evento.value
  if (!atual || atual.situacaoVenda !== 'DISPONIVEL') return false
  if (!atual.loteId || atual.preco === null) return false
  // Evento real pode nao informar `disponiveis`; nesse caso nao bloquear
  // (a RPC criar_reserva sera a fonte de verdade do estoque no futuro).
  if (typeof atual.disponiveis === 'number' && atual.disponiveis <= 0) return false
  return true
})

useSeoMeta({
  title: () =>
    evento.value ? `Checkout — ${evento.value.nome} | GZ1 Ingresso` : 'Checkout | GZ1 Ingresso'
})
</script>

<template>
  <PublicCatalogLoading v-if="pending" />

  <PublicCatalogError v-else-if="error" @retry="refresh" />

  <template v-else>
    <p
      v-if="avisoDev"
      class="mx-auto mt-4 w-full max-w-6xl px-4 text-xs text-amber-300 sm:px-6"
    >
      Modo desenvolvimento: exibindo dados de demonstração.
    </p>

    <CheckoutPage v-if="evento && podeComprar" :evento="evento" :origem="origem" />
    <CheckoutUnavailable v-else-if="evento" :evento="evento" />
    <PublicEventNotFound v-else />
  </template>
</template>
