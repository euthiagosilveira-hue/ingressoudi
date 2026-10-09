<script setup lang="ts">
import LotActivationSection from '~/components/lotes/LotActivationSection.vue'
import LotBasicSection from '~/components/lotes/LotBasicSection.vue'
import LotFormActions from '~/components/lotes/LotFormActions.vue'
import { useLotForm } from '~/composables/useLotForm'
import type { LotFormMode, LotFormValue, LotOrdemRef, LotPayload } from '~/types/lote'

const props = withDefaults(
  defineProps<{
    mode?: LotFormMode
    initialValue?: Partial<LotFormValue>
    ordens?: LotOrdemRef[]
    idAtual?: string
    ativacaoBloqueada?: boolean
    ordemBloqueada?: boolean
    submitLabel?: string
    submitting?: boolean
  }>(),
  {
    mode: 'create',
    initialValue: () => ({}),
    ordens: () => [],
    idAtual: '',
    ativacaoBloqueada: false,
    ordemBloqueada: false,
    submitLabel: 'Salvar lote',
    submitting: false
  }
)

const emit = defineEmits<{
  submit: [payload: LotPayload]
  cancel: []
}>()

const { valor, erros, validar, montarPayload } = useLotForm({
  initialValue: props.initialValue,
  ordens: props.ordens,
  idAtual: props.idAtual || undefined
})

function aoSubmeter() {
  if (!validar()) return
  emit('submit', montarPayload())
}
</script>

<template>
  <form class="space-y-6" novalidate @submit.prevent="aoSubmeter">
    <LotBasicSection :value="valor" :errors="erros" :ordem-bloqueada="props.ordemBloqueada" />
    <LotActivationSection
      :value="valor"
      :errors="erros"
      :bloqueada="props.ativacaoBloqueada"
    />
    <LotFormActions
      :submit-label="props.submitLabel"
      :submitting="props.submitting"
      @cancel="emit('cancel')"
    />
  </form>
</template>
