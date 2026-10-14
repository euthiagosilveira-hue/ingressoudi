<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'
import { CheckCircleIcon, EnvelopeIcon, ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import { slugDisponivel } from '~/services/auth/cadastro'
import {
  gerarSlug,
  mensagemErroCadastro,
  metadadosCadastro,
  slugValido,
  temErros,
  validarCadastro,
  type DadosCadastro,
  type ErrosCadastro
} from '~/utils/cadastro'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: `Crie sua conta de produtor | ${PLATAFORMA_NOME}`,
  description: 'Crie sua conta de produtor e comece a vender ingressos com Pix.'
})

const supabase = useSupabaseClient()
const config = useRuntimeConfig()

const form = reactive<DadosCadastro>({
  nome: '',
  email: '',
  senha: '',
  confirmacao: '',
  casaNome: '',
  casaSlug: '',
  termos: false
})
const erros = reactive<ErrosCadastro>({})
const erroGeral = ref('')
const enviando = ref(false)
const enviadoPara = ref('')

// Endereco segue o nome da casa ate o produtor editar manualmente.
const slugEditado = ref(false)
watch(
  () => form.casaNome,
  (nome) => {
    if (!slugEditado.value) form.casaSlug = gerarSlug(nome)
  }
)
function aoEditarSlug(valor: string) {
  slugEditado.value = true
  form.casaSlug = gerarSlug(valor)
}

const baseUrl = computed(() => {
  const site = String(config.public.siteUrl || '').replace(/\/+$/, '')
  if (site) return site
  return import.meta.client ? window.location.origin : ''
})
const hostExibicao = computed(() => baseUrl.value.replace(/^https?:\/\//, ''))

// Disponibilidade do endereco (debounce)
const disponibilidade = ref<'idle' | 'verificando' | 'livre' | 'ocupado' | 'erro'>('idle')
let timer: ReturnType<typeof setTimeout> | null = null
watch(
  () => form.casaSlug,
  (slug) => {
    if (timer) clearTimeout(timer)
    erros.casaSlug = undefined
    if (!slug || !slugValido(slug)) {
      disponibilidade.value = 'idle'
      return
    }
    disponibilidade.value = 'verificando'
    timer = setTimeout(async () => {
      try {
        const livre = await slugDisponivel(slug)
        if (slug === form.casaSlug) disponibilidade.value = livre ? 'livre' : 'ocupado'
      } catch {
        disponibilidade.value = 'erro'
      }
    }, 400)
  }
)
onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
})

function limparErros() {
  for (const chave of Object.keys(erros) as Array<keyof ErrosCadastro>) erros[chave] = undefined
  erroGeral.value = ''
}

async function cadastrar() {
  limparErros()
  const validacao = validarCadastro(form)
  Object.assign(erros, validacao)
  if (disponibilidade.value === 'ocupado') erros.casaSlug = 'Esse endereço já está em uso. Escolha outro.'
  if (temErros(erros)) return

  enviando.value = true
  try {
    const { data, error } = await supabase.auth.signUp({
      email: form.email.trim(),
      password: form.senha,
      options: {
        emailRedirectTo: `${baseUrl.value}/cadastro/concluir`,
        data: metadadosCadastro(form)
      }
    })
    if (error) {
      erroGeral.value = mensagemErroCadastro(error.message)
      return
    }
    // E-mail ja cadastrado: o Supabase devolve um usuario sem identidades.
    if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
      erroGeral.value = mensagemErroCadastro('user already registered')
      return
    }
    // Confirmacao de e-mail desligada: ja ha sessao, conclui direto.
    if (data.session) {
      await navigateTo('/cadastro/concluir')
      return
    }
    enviadoPara.value = form.email.trim()
  } catch {
    erroGeral.value = mensagemErroCadastro(null)
  } finally {
    enviando.value = false
  }
}
</script>

<template>
  <main class="flex min-h-[100dvh] items-center justify-center bg-[#050505] px-4 py-10 text-white">
    <section
      class="w-full max-w-lg rounded-3xl border border-amber-400/20 bg-zinc-950/90 p-7 shadow-2xl shadow-black/60 sm:p-9"
    >
      <header class="space-y-3 text-center">
        <NuxtLink to="/" class="text-2xl font-bold tracking-tight text-white">
          {{ PLATAFORMA_NOME }}<span class="text-amber-400">.</span>
        </NuxtLink>
        <h1 class="text-2xl font-bold text-white">Crie sua conta de produtor</h1>
        <p class="text-sm text-zinc-400">
          Sem mensalidade: você só paga uma taxa por ingresso vendido online. Após uma rápida análise, você publica
          seus eventos e vende com Pix.
        </p>
      </header>

      <!-- Link de confirmacao enviado -->
      <div v-if="enviadoPara" class="mt-8 space-y-4 text-center">
        <span class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-amber-400/10 text-amber-400">
          <EnvelopeIcon class="h-6 w-6" />
        </span>
        <p class="text-sm text-zinc-300">
          Enviamos um link de confirmação para <strong class="text-white">{{ enviadoPara }}</strong>.
          Abra o e-mail e clique no link para concluir o cadastro.
        </p>
        <p class="text-xs text-zinc-500">
          Não chegou? Confira a caixa de spam. Se já confirmou,
          <NuxtLink to="/cadastro/concluir" class="text-amber-400 hover:text-amber-300">entre aqui</NuxtLink>.
        </p>
      </div>

      <form v-else class="mt-8 space-y-5" novalidate @submit.prevent="cadastrar">
        <p
          v-if="erroGeral"
          role="alert"
          class="flex items-start gap-2 rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
        >
          <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
          <span>
            {{ erroGeral }}
            <NuxtLink
              v-if="erroGeral.includes('já tem conta')"
              to="/cadastro/concluir"
              class="font-semibold text-amber-300 underline"
            >Entrar</NuxtLink>
          </span>
        </p>

        <fieldset class="space-y-4">
          <legend class="mb-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500">Você</legend>
          <FormField :error="erros.nome">
            <BaseInput v-model="form.nome" label="Seu nome" name="nome" autocomplete="name" :invalid="!!erros.nome" />
          </FormField>
          <FormField :error="erros.email">
            <BaseInput
              v-model="form.email"
              label="E-mail"
              type="email"
              name="email"
              autocomplete="email"
              :invalid="!!erros.email"
            />
          </FormField>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <FormField :error="erros.senha">
              <BaseInput
                v-model="form.senha"
                label="Senha"
                type="password"
                name="password"
                autocomplete="new-password"
                :invalid="!!erros.senha"
              />
            </FormField>
            <FormField :error="erros.confirmacao">
              <BaseInput
                v-model="form.confirmacao"
                label="Confirmar senha"
                type="password"
                name="password-confirm"
                autocomplete="new-password"
                :invalid="!!erros.confirmacao"
              />
            </FormField>
          </div>
        </fieldset>

        <fieldset class="space-y-4">
          <legend class="mb-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500">
            Sua casa ou produtora
          </legend>
          <FormField :error="erros.casaNome">
            <BaseInput
              v-model="form.casaNome"
              label="Nome"
              name="casa"
              placeholder="Ex.: Bar do Samba"
              :invalid="!!erros.casaNome"
            />
          </FormField>
          <FormField :error="erros.casaSlug">
            <BaseInput
              :model-value="form.casaSlug"
              label="Endereço da sua página"
              name="endereco"
              placeholder="bar-do-samba"
              :invalid="!!erros.casaSlug || disponibilidade === 'ocupado'"
              @update:model-value="aoEditarSlug"
            />
            <p v-if="form.casaSlug" class="mt-1.5 truncate text-xs text-zinc-500">
              {{ hostExibicao }}/<span class="text-zinc-300">{{ form.casaSlug }}</span>
            </p>
            <p v-if="disponibilidade === 'verificando'" class="mt-1 text-xs text-zinc-500">Verificando...</p>
            <p v-else-if="disponibilidade === 'livre'" class="mt-1 flex items-center gap-1 text-xs text-emerald-400">
              <CheckCircleIcon class="h-4 w-4" /> Endereço disponível
            </p>
            <p v-else-if="disponibilidade === 'ocupado'" class="mt-1 text-xs text-red-400">
              Esse endereço já está em uso. Escolha outro.
            </p>
          </FormField>
        </fieldset>

        <div>
          <label class="flex cursor-pointer items-start gap-3 text-sm text-zinc-300">
            <input
              v-model="form.termos"
              type="checkbox"
              class="mt-0.5 h-4 w-4 shrink-0 rounded border-zinc-600 bg-zinc-900 accent-amber-400"
            />
            <span>
              Li e aceito os
              <NuxtLink to="/termos" target="_blank" class="text-amber-400 hover:text-amber-300">Termos de uso</NuxtLink>
              e a
              <NuxtLink to="/privacidade" target="_blank" class="text-amber-400 hover:text-amber-300">
                Política de privacidade</NuxtLink>.
            </span>
          </label>
          <p v-if="erros.termos" class="mt-1.5 text-xs text-red-400">{{ erros.termos }}</p>
        </div>

        <AppButton type="submit" variant="primary" size="lg" block :disabled="enviando">
          {{ enviando ? 'Criando conta...' : 'Criar conta' }}
        </AppButton>

        <p class="text-center text-xs text-zinc-500">
          Já tem conta?
          <NuxtLink to="/login" class="font-semibold text-amber-400 hover:text-amber-300">Entrar</NuxtLink>
        </p>
      </form>
    </section>
  </main>
</template>
