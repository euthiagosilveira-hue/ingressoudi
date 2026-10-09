<script setup lang="ts">
import { computed } from 'vue'
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import PageHeader from '~/components/PageHeader.vue'
import EventBasicInfoSection from '~/components/eventos/EventBasicInfoSection.vue'
import EventCapacitySection from '~/components/eventos/EventCapacitySection.vue'
import EventDescriptionSection from '~/components/eventos/EventDescriptionSection.vue'
import EventFormActions from '~/components/eventos/EventFormActions.vue'
import EventImageSection from '~/components/eventos/EventImageSection.vue'
import EventPublicationSection from '~/components/eventos/EventPublicationSection.vue'
import { useEventForm } from '~/composables/useEventForm'
import type { EventFormMode, EventFormValue, EventPayload } from '~/types/evento'

const props = withDefaults(
  defineProps<{
    mode?: EventFormMode
    initialValue?: Partial<EventFormValue>
    eventoId?: string | null
  }>(),
  {
    mode: 'create',
    initialValue: () => ({}),
    eventoId: null
  }
)

const emit = defineEmits<{
  submit: [payload: EventPayload]
  cancel: []
}>()

const {
  valor,
  erros,
  enviando,
  slugEditadoManualmente,
  marcarSlugManual,
  usarUrlAutomatica,
  validar,
  montarPayload
} = useEventForm({
  initialValue: props.initialValue
})

const modoCriacao = computed(() => props.mode === 'create')
const titulo = computed(() => (modoCriacao.value ? 'Criar evento' : 'Editar evento'))

function aoSubmeter() {
  if (!validar()) return
  emit('submit', montarPayload())
}

function aoCancelar() {
  emit('cancel')
}

function visualizarPublico() {
  if (props.mode === 'create' || !valor.slug) return
  navigateTo(`/eventos/${valor.slug}`)
}
</script>

<template>
  <div class="mx-auto w-full max-w-5xl space-y-6">
    <NuxtLink
      to="/eventos"
      class="inline-flex items-center gap-2 text-sm text-zinc-400 transition-colors duration-150 hover:text-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
    >
      <ArrowLeftIcon class="h-4 w-4" />
      Voltar para eventos
    </NuxtLink>

    <PageHeader :title="titulo" subtitle="Preencha as informações do seu evento.">
      <template #actions>
        <AppButton variant="outline" :disabled="modoCriacao" @click="visualizarPublico">
          Visualizar público
        </AppButton>
        <AppButton variant="primary" :disabled="enviando" @click="aoSubmeter">
          Salvar evento
        </AppButton>
      </template>
    </PageHeader>

    <EventBasicInfoSection
      :value="valor"
      :errors="erros"
      :manual-slug="slugEditadoManualmente"
      @slug-manual="marcarSlugManual"
      @slug-auto="usarUrlAutomatica"
    />
    <EventImageSection :value="valor" />
    <EventDescriptionSection :value="valor" :errors="erros" />
    <EventCapacitySection
      :value="valor"
      :errors="erros"
      :evento-id="props.eventoId"
      :evento-nome="valor.nome"
    />
    <EventPublicationSection :value="valor" />

    <EventFormActions :submitting="enviando" @cancel="aoCancelar" @submit="aoSubmeter" />
  </div>
</template>
