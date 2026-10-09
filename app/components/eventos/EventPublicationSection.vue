<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import EventStatusBadge from '~/components/eventos/EventStatusBadge.vue'
import SegmentedControl from '~/components/SegmentedControl.vue'
import type { EventFormValue } from '~/types/evento'
import type { SelectOption } from '~/types/ui'

const props = defineProps<{
  value: EventFormValue
}>()

const publicacaoOptions: SelectOption[] = [
  { value: 'RASCUNHO', label: 'Rascunho' },
  { value: 'PUBLICADO', label: 'Publicado' }
]

const vendasOptions: SelectOption[] = [
  { value: 'ENCERRADAS', label: 'Encerradas' },
  { value: 'ABERTAS', label: 'Abertas' }
]
</script>

<template>
  <BaseCard class="space-y-6">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      5. Publicação e vendas
    </h2>

    <div class="space-y-2">
      <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Publicação</p>
      <SegmentedControl v-model="props.value.publicacaoStatus" :options="publicacaoOptions" />
      <p class="text-xs text-zinc-500">
        Eventos em rascunho não aparecem no catálogo público.
      </p>
    </div>

    <div class="space-y-2">
      <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Vendas</p>
      <SegmentedControl v-model="props.value.vendasStatus" :options="vendasOptions" />
      <p class="text-xs text-zinc-500">
        As vendas serão encerradas automaticamente no horário de início do evento.
      </p>
    </div>

    <div class="space-y-2">
      <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Status do evento</p>
      <EventStatusBadge status="AGENDADO" />
      <p class="text-xs text-zinc-500">O evento será criado inicialmente como agendado.</p>
    </div>
  </BaseCard>
</template>
