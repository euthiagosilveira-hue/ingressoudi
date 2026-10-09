<script setup lang="ts">
import EntryMobileCard from '~/components/entradas/EntryMobileCard.vue'
import type { EntryListItem } from '~/types/entrada'

const props = defineProps<{
  entradas: EntryListItem[]
}>()

const emit = defineEmits<{
  action: [{ id: string; ingressoId: string; pedidoId: string; action: string }]
}>()
</script>

<template>
  <div class="flex flex-col gap-4">
    <EntryMobileCard
      v-for="entrada in props.entradas"
      :key="entrada.id"
      :entrada="entrada"
      @action="emit('action', $event)"
    />
  </div>
</template>
