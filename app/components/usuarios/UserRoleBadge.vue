<script setup lang="ts">
import { computed } from 'vue'

import type { PerfilUsuario } from '~/types/usuario'

const props = defineProps<{
  perfil: PerfilUsuario
}>()

const info = computed(() => {
  if (props.perfil === 'ADMINISTRADOR') {
    return { label: 'Administrador', classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300' }
  }
  if (props.perfil === 'SOCIO') {
    return { label: 'Sócio do Evento', classes: 'border-sky-400/30 bg-sky-400/10 text-sky-300' }
  }
  return { label: 'Portaria', classes: 'border-zinc-600/40 bg-zinc-800/80 text-zinc-300' }
})
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    {{ info.label }}
  </span>
</template>
