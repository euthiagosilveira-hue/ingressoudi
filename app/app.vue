<script setup lang="ts">
import { computed } from 'vue'

import { PLATAFORMA_NOME } from '~/utils/marca'
import { IMAGEM_SOCIAL, urlAbsoluta, urlCanonica } from '~/utils/seo'

// Endereco canonico e cartao de compartilhamento padrao de todas as paginas.
// Cada pagina pode sobrescrever titulo, descricao e imagem com useSeoMeta.
const route = useRoute()
const siteUrl = String(useRuntimeConfig().public.siteUrl ?? '')
const canonica = computed(() => urlCanonica(siteUrl, route.path))

useHead({
  link: [{ rel: 'canonical', href: canonica }]
})
useSeoMeta({
  ogSiteName: PLATAFORMA_NOME,
  ogLocale: 'pt_BR',
  ogType: 'website',
  ogUrl: canonica,
  ogImage: urlAbsoluta(siteUrl, IMAGEM_SOCIAL),
  twitterCard: 'summary_large_image'
})
</script>

<template>
  <div>
    <NuxtRouteAnnouncer />
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </div>
</template>
