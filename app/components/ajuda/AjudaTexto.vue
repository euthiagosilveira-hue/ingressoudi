<script setup lang="ts">
import { computed } from 'vue'

import { partesTexto } from '~/utils/ajuda'

const props = defineProps<{ texto: string }>()

// Negrito marcado com **texto**, sem v-html.
const partes = computed(() => partesTexto(props.texto))
</script>

<template>
  <span>
    <template v-for="(parte, i) in partes" :key="i">
      <strong v-if="parte.negrito" class="font-semibold text-white">{{ parte.texto }}</strong>
      <template v-else>{{ parte.texto }}</template>
    </template>
  </span>
</template>
