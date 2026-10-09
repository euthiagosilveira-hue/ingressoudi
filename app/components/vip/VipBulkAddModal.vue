<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import FormField from '~/components/FormField.vue'
import { parseNomesVip, validarLoteVip } from '~/utils/vip'

const props = withDefaults(
  defineProps<{
    open: boolean
    submitting?: boolean
  }>(),
  { submitting: false }
)

const emit = defineEmits<{
  submit: [nomes: string[]]
  cancel: []
}>()

const texto = ref('')
const erro = ref('')

const nomes = computed(() => parseNomesVip(texto.value))
const quantidade = computed(() => nomes.value.length)
const previa = computed(() => nomes.value.slice(0, 3))
const restante = computed(() => Math.max(quantidade.value - previa.value.length, 0))

watch(
  () => props.open,
  (aberto) => {
    if (!aberto) return
    texto.value = ''
    erro.value = ''
  }
)

function enviar() {
  erro.value = validarLoteVip(nomes.value) ?? ''
  if (erro.value) return
  emit('submit', nomes.value)
}
</script>

<template>
  <BaseModal
    :open="props.open"
    size="lg"
    title="Adicionar vários convidados"
    subtitle="Digite ou cole um nome por linha."
    @close="emit('cancel')"
  >
    <form class="space-y-4" novalidate @submit.prevent="enviar">
      <FormField label="Convidados" :error="erro || undefined">
        <BaseTextarea
          v-model="texto"
          :rows="8"
          placeholder="João Silva&#10;Maria Souza&#10;Carlos Ferreira"
        />
      </FormField>

      <div v-if="quantidade > 0" class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
        <p class="text-sm font-semibold text-white">
          {{ quantidade }} convidado{{ quantidade === 1 ? '' : 's' }} serão adicionados
        </p>
        <ul class="mt-1.5 space-y-0.5 text-xs text-zinc-500">
          <li v-for="(nome, indice) in previa" :key="indice">{{ nome }}</li>
          <li v-if="restante > 0" class="text-zinc-600">+{{ restante }} convidado(s)</li>
        </ul>
      </div>
    </form>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.submitting" @click="emit('cancel')">
          Cancelar
        </AppButton>
        <AppButton variant="primary" :disabled="props.submitting" @click="enviar">
          {{
            props.submitting
              ? 'Adicionando...'
              : `Adicionar${quantidade > 0 ? ' ' + quantidade : ''}`
          }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
