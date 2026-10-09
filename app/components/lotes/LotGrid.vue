<script setup lang="ts">
import LotCard from '~/components/lotes/LotCard.vue'
import LotEmptyState from '~/components/lotes/LotEmptyState.vue'
import type { LotListItem } from '~/types/lote'

const props = defineProps<{
  lotes: LotListItem[]
  vendasAbertas: boolean
}>()

const emit = defineEmits<{
  action: [{ id: string; action: string }]
  create: []
}>()
</script>

<template>
  <div>
    <LotEmptyState v-if="props.lotes.length === 0" @create="emit('create')" />

    <div v-else class="grid grid-cols-1 gap-5 lg:grid-cols-2 xl:grid-cols-3">
      <LotCard
        v-for="lote in props.lotes"
        :key="lote.id"
        :lote="lote"
        :vendas-abertas="props.vendasAbertas"
        @action="emit('action', { id: lote.id, action: $event })"
      />
    </div>
  </div>
</template>
