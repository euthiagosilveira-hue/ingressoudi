<script setup lang="ts">
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'

const { organizacao } = useOrganizacaoPublica()
const ano = new Date().getFullYear()
</script>

<template>
  <footer class="border-t border-zinc-800 bg-black">
    <div
      class="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-8 text-sm text-zinc-500 sm:flex-row sm:items-center sm:justify-between sm:px-6"
    >
      <p class="font-semibold text-zinc-300">{{ organizacao?.nome ?? PLATAFORMA_NOME }}</p>
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-6">
        <nav class="flex gap-4" aria-label="Documentos legais">
          <NuxtLink to="/termos" class="hover:text-zinc-300">Termos de uso</NuxtLink>
          <NuxtLink to="/privacidade" class="hover:text-zinc-300">Privacidade</NuxtLink>
        </nav>
        <p v-if="organizacao">
          Ingressos por <NuxtLink to="/" class="text-zinc-300 hover:text-amber-400">{{ PLATAFORMA_NOME }}</NuxtLink>
        </p>
        <p v-else>© {{ ano }} {{ PLATAFORMA_NOME }}. Todos os direitos reservados.</p>
      </div>
    </div>
  </footer>
</template>
