<script setup lang="ts">
import { computed } from 'vue'

import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { COR_PADRAO, corTextoContraste, normalizarCor } from '~/utils/marca'

const { organizacao } = useOrganizacaoPublica()

// Cor de destaque da casa disponivel para os componentes via CSS.
const estilo = computed(() => {
  const cor = normalizarCor(organizacao.value?.corPrimaria) ?? COR_PADRAO
  return { '--cor-casa': cor, '--cor-casa-texto': corTextoContraste(cor) }
})
</script>

<template>
  <div class="flex min-h-screen flex-col bg-zinc-950 text-white" :style="estilo">
    <PublicHeader />
    <main class="flex-1">
      <slot />
    </main>
    <PublicFooter />
  </div>
</template>
