<script setup lang="ts">
import EventCard from '~/components/eventos/EventCard.vue'
import EventEmptyState from '~/components/eventos/EventEmptyState.vue'
import type { EventListItem } from '~/types/evento'

const props = defineProps<{
  events: EventListItem[]
}>()

const emit = defineEmits<{
  edit: [id: string]
  action: [{ id: string; action: string }]
  create: []
}>()
</script>

<template>
  <div>
    <p v-if="props.events.length > 0" class="mb-4 text-sm text-zinc-500">
      {{ props.events.length }}
      {{ props.events.length === 1 ? 'evento encontrado' : 'eventos encontrados' }}
    </p>

    <EventEmptyState v-if="props.events.length === 0" @create="emit('create')" />

    <div v-else class="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-3">
      <EventCard
        v-for="evento in props.events"
        :key="evento.id"
        :event="evento"
        @edit="emit('edit', evento.id)"
        @action="emit('action', { id: evento.id, action: $event })"
      />
    </div>
  </div>
</template>
