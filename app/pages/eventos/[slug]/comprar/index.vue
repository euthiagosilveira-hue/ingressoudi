<script setup lang="ts">
import { computed } from 'vue'

import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import { resolverEventoPublico } from '~/services/public/catalogo'
import { tituloPublico } from '~/utils/marca'
import { rotaCheckout } from '~/utils/rotasPublicas'

/** Link antigo /eventos/{slug}/comprar: redireciona para /{casa}/{evento}/comprar. */
const route = useRoute()
const slug = computed(() => String(route.params.slug ?? ''))

const destino = await resolverEventoPublico(slug.value).catch(() => null)
if (destino) {
  await navigateTo(rotaCheckout(destino.organizacaoSlug, destino.eventoSlug), { redirectCode: 301 })
}

useSeoMeta({ title: tituloPublico('Checkout') })
</script>

<template>
  <PublicEventNotFound />
</template>
