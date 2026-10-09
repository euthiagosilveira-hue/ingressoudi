<script setup lang="ts">
import { reactive, ref, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import FormField from '~/components/FormField.vue'
import type { ConviteUsuarioInput, PerfilUsuario } from '~/types/usuario'
import {
  PERFIS_USUARIO,
  formularioValido,
  rotuloPerfil,
  validarConvite
} from '~/utils/usuarios'

const props = defineProps<{
  open: boolean
  enviando?: boolean
}>()

const emit = defineEmits<{
  close: []
  submit: [input: ConviteUsuarioInput]
}>()

const form = reactive({
  nome: '',
  email: '',
  perfil: 'PORTARIA' as PerfilUsuario
})
const erros = ref<{ nome?: string; email?: string; perfil?: string }>({})

const perfilOptions = PERFIS_USUARIO.map((perfil) => ({ value: perfil, label: rotuloPerfil(perfil) }))

watch(
  () => props.open,
  (aberto) => {
    if (aberto) {
      form.nome = ''
      form.email = ''
      form.perfil = 'PORTARIA'
      erros.value = {}
    }
  }
)

function enviar() {
  const validacao = validarConvite({ nome: form.nome, email: form.email, perfil: form.perfil })
  erros.value = validacao
  if (!formularioValido(validacao)) return
  emit('submit', { nome: form.nome, email: form.email, perfil: form.perfil })
}
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Convidar usuário"
    subtitle="Um convite será enviado por e-mail."
    @close="emit('close')"
  >
    <div class="space-y-4">
      <FormField label="Nome" required :error="erros.nome">
        <BaseInput v-model="form.nome" placeholder="Nome completo" :invalid="!!erros.nome" />
      </FormField>

      <FormField label="E-mail" required :error="erros.email">
        <BaseInput
          v-model="form.email"
          type="email"
          placeholder="email@exemplo.com"
          :invalid="!!erros.email"
        />
      </FormField>

      <FormField label="Perfil" required :error="erros.perfil">
        <BaseSelect v-model="form.perfil" :options="perfilOptions" />
      </FormField>
    </div>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.enviando" @click="emit('close')">
          Cancelar
        </AppButton>
        <AppButton variant="primary" :disabled="props.enviando" @click="enviar">
          {{ props.enviando ? 'Enviando...' : 'Enviar convite' }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
