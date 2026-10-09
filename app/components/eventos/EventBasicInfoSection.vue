<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import EventUrlField from '~/components/eventos/EventUrlField.vue'
import type { EventFormErrors, EventFormValue } from '~/types/evento'

defineProps<{
  value: EventFormValue
  errors: EventFormErrors
  manualSlug: boolean
}>()

const emit = defineEmits<{
  'slug-manual': []
  'slug-auto': []
}>()
</script>

<template>
  <BaseCard class="space-y-5">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      1. Informações básicas
    </h2>

    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <FormField label="Nome do evento" required :error="errors.nome">
        <BaseInput
          v-model="value.nome"
          placeholder="Ex.: Banda Conexão"
          :invalid="!!errors.nome"
        />
      </FormField>

      <EventUrlField
        v-model="value.slug"
        :manual="manualSlug"
        :error="errors.slug"
        @edit-manual="emit('slug-manual')"
        @use-auto="emit('slug-auto')"
      />

      <FormField label="Data do evento" required :error="errors.dataInicio">
        <BaseInput v-model="value.dataInicio" type="date" :invalid="!!errors.dataInicio" />
      </FormField>

      <FormField label="Horário de início" required :error="errors.horaInicio">
        <BaseInput v-model="value.horaInicio" type="time" :invalid="!!errors.horaInicio" />
      </FormField>

      <FormField label="Local" required :error="errors.local">
        <BaseInput
          v-model="value.local"
          placeholder="Ex.: Galeria Zero 1"
          :invalid="!!errors.local"
        />
      </FormField>

      <FormField label="Endereço" required :error="errors.endereco">
        <BaseInput
          v-model="value.endereco"
          placeholder="Ex.: Av. ..., nº ..."
          :invalid="!!errors.endereco"
        />
      </FormField>
    </div>
  </BaseCard>
</template>
