<script setup lang="ts">
import BasePagination from '~/components/BasePagination.vue'

defineProps<{
  pagina: number
  totalPaginas: number
}>()

const emit = defineEmits<{
  ir: [pagina: number]
}>()
</script>

<template>
  <BasePagination :pagina="pagina" :total-paginas="totalPaginas" @ir="emit('ir', $event)" />
</template>
