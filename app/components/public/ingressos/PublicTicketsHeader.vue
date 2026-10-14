<script setup lang="ts">
import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { rotaEvento } from '~/utils/rotasPublicas'

const props = defineProps<{
  eventoSlug: string
  eventoNome: string
}>()

const { organizacao: organizacaoPublica } = useOrganizacaoPublica()
</script>

<template>
  <header class="space-y-2">
    <NuxtLink
      :to="rotaEvento(organizacaoPublica?.slug, props.eventoSlug)"
      class="inline-flex items-center gap-1 text-xs font-medium uppercase tracking-wide text-zinc-500 transition-colors hover:text-zinc-300"
    >
      ← {{ props.eventoNome }}
    </NuxtLink>
    <h1 class="text-2xl font-bold text-white">Seus ingressos</h1>
  </header>
</template>
