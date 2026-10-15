<script setup lang="ts">
import { computed } from 'vue'

import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'
import { itensNavegacaoPublica } from '~/utils/publicNav'

const { organizacao } = useOrganizacaoPublica()

const navItems = computed(() => itensNavegacaoPublica(organizacao.value?.slug))
const inicio = computed(() => (organizacao.value ? `/${organizacao.value.slug}` : '/'))
</script>

<template>
  <header class="sticky top-0 z-40 border-b border-zinc-800 bg-black/90 backdrop-blur">
    <div v-if="organizacao" class="h-1 w-full" style="background: var(--cor-casa)" role="presentation" />
    <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
      <NuxtLink
        :to="inicio"
        class="flex min-w-0 items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      >
        <img
          v-if="organizacao?.logoUrl"
          :src="organizacao.logoUrl"
          :alt="organizacao.nome"
          class="h-8 w-auto"
        />
        <span v-else-if="organizacao" class="truncate text-lg font-bold text-white">
          {{ organizacao.nome }}
        </span>
        <span
          v-else
          class="text-2xl font-extrabold tracking-tight text-white drop-shadow-[0_0_16px_rgba(217,177,56,0.35)]"
        >
          {{ PLATAFORMA_NOME }}<span class="text-[#E8C24A]">.</span>
        </span>
      </NuxtLink>

      <nav class="flex shrink-0 items-center gap-4 text-sm sm:gap-5">
        <NuxtLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="text-zinc-300 transition-colors hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        >
          {{ item.label }}
        </NuxtLink>
      </nav>
    </div>
  </header>
</template>
