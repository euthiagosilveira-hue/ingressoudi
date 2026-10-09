<script setup lang="ts">
import { computed } from 'vue'

import type { PerfilUsuario } from '~/types/usuario'

const props = defineProps<{
  perfil: PerfilUsuario
}>()

const info = computed(() =>
  props.perfil === 'ADMINISTRADOR'
    ? { label: 'Administrador', classes: 'border-amber-400/30 bg-amber-400/10 text-amber-300' }
    : { label: 'Portaria', classes: 'border-zinc-600/40 bg-zinc-800/80 text-zinc-300' }
)
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
    :class="info.classes"
  >
    {{ info.label }}
  </span>
</template>
