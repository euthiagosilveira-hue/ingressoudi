<script setup lang="ts">
import { reactive, ref, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import FormField from '~/components/FormField.vue'
import UserInviteLinkPanel from '~/components/usuarios/UserInviteLinkPanel.vue'
import type { ConviteUsuarioInput, PerfilUsuario, ResultadoConvite } from '~/types/usuario'
import {
  PERFIS_USUARIO,
  formularioValido,
  rotuloPerfil,
  validarConvite
} from '~/utils/usuarios'

const props = defineProps<{
  open: boolean
  enviando?: boolean
  /** Preenchido depois que o convite foi criado. */
  resultado?: ResultadoConvite | null
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
const nomeConvidado = ref('')
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
  nomeConvidado.value = form.nome.trim()
  emit('submit', { nome: form.nome, email: form.email, perfil: form.perfil })
}
</script>

<template>
  <BaseModal
    :open="props.open"
    :title="props.resultado ? 'Convite criado' : 'Convidar usuário'"
    :subtitle="
      props.resultado
        ? undefined
        : 'Você recebe um link para enviar à pessoa pelo WhatsApp ou como preferir.'
    "
    @close="emit('close')"
  >
    <template v-if="props.resultado">
      <UserInviteLinkPanel
        v-if="props.resultado.link"
        :nome="nomeConvidado"
        :link="props.resultado.link"
      />
      <div v-else class="space-y-2 text-sm text-zinc-300" role="status">
        <p>
          <span class="font-semibold text-white">{{ nomeConvidado }}</span> já tem conta no
          Ingressoudi e foi adicionado(a) à sua organização.
        </p>
        <p v-if="props.resultado.pendente" class="text-zinc-400">
          A pessoa ainda não criou a senha do convite que recebeu de outra organização. Peça para
          ela concluir aquele convite; depois disso ela verá a sua organização no painel.
        </p>
        <p v-else class="text-zinc-400">
          Ela entra com o mesmo e-mail e senha de sempre e já verá a sua organização no painel.
        </p>
      </div>
    </template>

    <div v-else class="space-y-4">
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
      <div v-if="props.resultado" class="flex justify-end">
        <AppButton variant="ghost" @click="emit('close')">Concluir</AppButton>
      </div>
      <div v-else class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.enviando" @click="emit('close')">
          Cancelar
        </AppButton>
        <AppButton variant="primary" :disabled="props.enviando" @click="enviar">
          {{ props.enviando ? 'Gerando convite...' : 'Gerar convite' }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
