<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseModal from '~/components/BaseModal.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import FormField from '~/components/FormField.vue'
import type { EdicaoUsuarioInput, PerfilUsuario, UsuarioListItem } from '~/types/usuario'
import {
  PERFIS_USUARIO,
  formularioValido,
  rotuloPerfil,
  validarEdicao
} from '~/utils/usuarios'

const props = defineProps<{
  open: boolean
  usuario: UsuarioListItem | null
  salvando?: boolean
}>()

const emit = defineEmits<{
  close: []
  submit: [input: EdicaoUsuarioInput]
}>()

const form = reactive({
  nome: '',
  email: '',
  perfil: 'PORTARIA' as PerfilUsuario,
  ativo: 'true'
})
const erros = ref<{ nome?: string; perfil?: string }>({})

const perfilOptions = PERFIS_USUARIO.map((perfil) => ({ value: perfil, label: rotuloPerfil(perfil) }))
const statusOptions = [
  { value: 'true', label: 'Ativo' },
  { value: 'false', label: 'Inativo' }
]

const ultimoAdmin = computed(() => props.usuario?.ehUltimoAdminAtivo === true)

watch(
  () => props.open,
  (aberto) => {
    if (aberto && props.usuario) {
      form.nome = props.usuario.nome
      form.email = props.usuario.email
      form.perfil = props.usuario.perfil
      form.ativo = props.usuario.ativo ? 'true' : 'false'
      erros.value = {}
    }
  }
)

function enviar() {
  if (!props.usuario) return
  const perfil = ultimoAdmin.value ? 'ADMINISTRADOR' : form.perfil
  const ativo = ultimoAdmin.value ? true : form.ativo === 'true'
  const validacao = validarEdicao({ id: props.usuario.id, nome: form.nome, perfil, ativo })
  erros.value = validacao
  if (!formularioValido(validacao)) return
  emit('submit', { id: props.usuario.id, nome: form.nome, perfil, ativo })
}
</script>

<template>
  <BaseModal
    :open="props.open"
    title="Editar usuário"
    subtitle="O e-mail não pode ser alterado nesta etapa."
    @close="emit('close')"
  >
    <div class="space-y-4">
      <FormField label="Nome" required :error="erros.nome">
        <BaseInput v-model="form.nome" placeholder="Nome completo" :invalid="!!erros.nome" />
      </FormField>

      <FormField label="E-mail" hint="Vinculado à conta de acesso (somente leitura).">
        <BaseInput v-model="form.email" type="email" disabled />
      </FormField>

      <FormField label="Perfil" required :error="erros.perfil">
        <p
          v-if="ultimoAdmin"
          class="rounded-lg border border-zinc-700 bg-zinc-950 px-3.5 py-2.5 text-sm text-zinc-300"
        >
          Administrador
        </p>
        <BaseSelect v-else v-model="form.perfil" :options="perfilOptions" />
      </FormField>

      <FormField label="Status">
        <p
          v-if="ultimoAdmin"
          class="rounded-lg border border-zinc-700 bg-zinc-950 px-3.5 py-2.5 text-sm text-zinc-300"
        >
          Ativo
        </p>
        <BaseSelect v-else v-model="form.ativo" :options="statusOptions" />
      </FormField>

      <p
        v-if="ultimoAdmin"
        class="rounded-xl border border-amber-400/30 bg-amber-400/5 p-3 text-xs text-amber-300"
      >
        Último administrador ativo: não pode ser desativado nem rebaixado.
      </p>
    </div>

    <template #footer>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <AppButton variant="ghost" :disabled="props.salvando" @click="emit('close')">
          Cancelar
        </AppButton>
        <AppButton variant="primary" :disabled="props.salvando" @click="enviar">
          {{ props.salvando ? 'Salvando...' : 'Salvar alterações' }}
        </AppButton>
      </div>
    </template>
  </BaseModal>
</template>
