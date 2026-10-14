<script setup lang="ts">
import { CONTATO_EMAIL, PLATAFORMA_NOME } from '~/utils/marca'
import { TERMOS_VERSAO } from '~/utils/cadastro'

defineProps<{
  titulo: string
}>()
</script>

<template>
  <div class="mx-auto w-full max-w-3xl px-4 py-12 sm:px-6 sm:py-16">
    <p class="text-xs font-semibold uppercase tracking-[0.2em] text-amber-400">{{ PLATAFORMA_NOME }}</p>
    <h1 class="mt-3 text-3xl font-bold text-white sm:text-4xl">{{ titulo }}</h1>
    <p class="mt-2 text-xs text-zinc-500">Versão {{ TERMOS_VERSAO }} · atualizado em outubro de 2026</p>

    <article
      class="mt-8 space-y-4 text-sm leading-relaxed text-zinc-300 [&_h2]:pt-4 [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:text-white [&_li]:ml-5 [&_li]:list-disc [&_ul]:space-y-1"
    >
      <slot />

      <h2>Contato</h2>
      <p v-if="CONTATO_EMAIL">
        Dúvidas sobre este documento:
        <a :href="`mailto:${CONTATO_EMAIL}`" class="text-amber-400 hover:text-amber-300">{{ CONTATO_EMAIL }}</a>.
      </p>
      <p v-else>
        Dúvidas sobre este documento podem ser enviadas pelos canais de atendimento informados pelo organizador do
        evento ou pela plataforma.
      </p>
    </article>
  </div>
</template>
