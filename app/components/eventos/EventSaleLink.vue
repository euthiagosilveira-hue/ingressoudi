<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import CopyLinkField from '~/components/CopyLinkField.vue'
import { useCopiarLinkEvento } from '~/composables/useCopiarLinkEvento'

/** Link de venda (pagina publica) do evento com botao Copiar. */
const props = defineProps<{
  slug: string
}>()

const { linkEvento } = useCopiarLinkEvento()

// Monta o link so no cliente para nao divergir da hidratacao (usa window.location).
const montado = ref(false)
onMounted(() => {
  montado.value = true
})
const link = computed(() => (montado.value && props.slug ? linkEvento(props.slug) : ''))
</script>

<template>
  <CopyLinkField v-if="props.slug" rotulo="Link de venda" :link="link" aria-copiar="Copiar link de venda" />
</template>
