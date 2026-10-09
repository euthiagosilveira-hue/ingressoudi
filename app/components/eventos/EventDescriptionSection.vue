<script setup lang="ts">
import BaseCard from '~/components/BaseCard.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import FormField from '~/components/FormField.vue'
import type { EventFormErrors, EventFormValue } from '~/types/evento'

const props = defineProps<{
  value: EventFormValue
  errors: EventFormErrors
}>()

const MAX_CARACTERES = 500
</script>

<template>
  <BaseCard class="space-y-5">
    <h2 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      3. Descrição do evento
    </h2>

    <FormField :error="errors.descricao">
      <BaseTextarea
        v-model="props.value.descricao"
        :rows="6"
        :maxlength="MAX_CARACTERES"
        placeholder="Conte um pouco sobre o evento..."
        :invalid="!!errors.descricao"
      />
      <p class="mt-1.5 text-right text-xs text-zinc-500">
        {{ (props.value.descricao || '').length }} / {{ MAX_CARACTERES }}
      </p>
    </FormField>
  </BaseCard>
</template>
