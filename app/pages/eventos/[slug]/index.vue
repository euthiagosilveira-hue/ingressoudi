<script setup lang="ts">
import { computed } from 'vue'

import PublicEventNotFound from '~/components/public/eventos/PublicEventNotFound.vue'
import { resolverEventoPublico } from '~/services/public/catalogo'
import { tituloPublico } from '~/utils/marca'
import { rotaEvento } from '~/utils/rotasPublicas'

/**
 * Link antigo /eventos/{slug}: redireciona (301) para /{casa}/{evento} quando o
 * slug identifica um unico evento publicado. Caso contrario, "nao encontrado".
 */
const route = useRoute()
const slug = computed(() => String(route.params.slug ?? ''))

const destino = await resolverEventoPublico(slug.value).catch(() => null)
if (destino) {
  await navigateTo(rotaEvento(destino.organizacaoSlug, destino.eventoSlug), { redirectCode: 301 })
}

useSeoMeta({ title: tituloPublico('Evento') })
</script>

<template>
  <PublicEventNotFound />
</template>
