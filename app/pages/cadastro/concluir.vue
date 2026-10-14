<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import { concluirCadastroProdutor, lerMetadadosCadastro } from '~/services/auth/cadastro'
import { TERMOS_VERSAO, gerarSlug, mensagemErroCadastro, slugValido } from '~/utils/cadastro'
import { extrairErroConvite } from '~/utils/convite'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: `Concluir cadastro | ${PLATAFORMA_NOME}`,
  description: 'Conclua o cadastro da sua casa.'
})

const supabase = useSupabaseClient()

type Estado = 'verificando' | 'login' | 'dados' | 'processando' | 'erro'
const estado = ref<Estado>('verificando')
const mensagem = ref('')
const ocupado = ref(false)

const login = reactive({ email: '', senha: '' })
const dados = reactive({ nome: '', casaNome: '', casaSlug: '', termos: false })
const errosDados = reactive<{ nome?: string; casaNome?: string; casaSlug?: string; termos?: string }>({})
// Endereco acompanha o nome ate ser editado manualmente.
const slugEditado = ref(false)

async function sessaoAtual(): Promise<boolean> {
  for (let tentativa = 0; tentativa < 10; tentativa += 1) {
    const { data } = await supabase.auth.getSession()
    if (data.session?.user?.id) return true
    await new Promise((resolver) => setTimeout(resolver, 200))
  }
  return false
}

async function concluir(meta: { nome: string; casa_nome: string; casa_slug: string; termos_versao: string }) {
  estado.value = 'processando'
  mensagem.value = ''
  try {
    await concluirCadastroProdutor(meta)
    // Recarrega a aplicacao ja na casa nova (painel com aviso de analise).
    window.location.assign('/painel')
  } catch (e) {
    const texto = e instanceof Error ? e.message : mensagemErroCadastro(null)
    if (texto.includes('endereço')) {
      dados.nome = meta.nome
      dados.casaNome = meta.casa_nome
      dados.casaSlug = meta.casa_slug
      dados.termos = true
      slugEditado.value = true
      errosDados.casaSlug = texto
      estado.value = 'dados'
      return
    }
    mensagem.value = texto
    estado.value = 'erro'
  }
}

async function prosseguir() {
  const { data } = await supabase.auth.getUser()
  const meta = lerMetadadosCadastro(data.user?.user_metadata)
  if (!meta) {
    // Conta sem dados de cadastro (ex.: e-mail ja existente): pede os dados da casa.
    dados.nome = String(data.user?.user_metadata?.nome ?? '')
    estado.value = 'dados'
    return
  }
  await concluir(meta)
}

onMounted(async () => {
  const search = window.location.search
  const hash = window.location.hash

  if (extrairErroConvite(search, hash)) {
    mensagem.value = 'Este link expirou ou já foi utilizado. Entre com seu e-mail e senha para concluir.'
    estado.value = 'login'
    return
  }

  const code = new URLSearchParams(search.replace(/^\?/, '')).get('code')
  if (code) await supabase.auth.exchangeCodeForSession(code).catch(() => {})

  const hashParams = new URLSearchParams(hash.replace(/^#/, ''))
  const accessToken = hashParams.get('access_token')
  const refreshToken = hashParams.get('refresh_token')
  if (accessToken && refreshToken) {
    await supabase.auth.setSession({ access_token: accessToken, refresh_token: refreshToken }).catch(() => {})
  }

  if (await sessaoAtual()) {
    await prosseguir()
  } else {
    estado.value = 'login'
  }
})

async function entrar() {
  mensagem.value = ''
  if (!login.email.trim() || !login.senha) {
    mensagem.value = 'Informe e-mail e senha.'
    return
  }
  ocupado.value = true
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: login.email.trim(),
      password: login.senha
    })
    if (error) {
      mensagem.value = mensagemErroCadastro(error.message)
      return
    }
    await prosseguir()
  } finally {
    ocupado.value = false
  }
}

function aoEditarCasa(valor: string) {
  dados.casaNome = valor
  if (!slugEditado.value) dados.casaSlug = gerarSlug(valor)
}
function aoEditarSlug(valor: string) {
  slugEditado.value = true
  dados.casaSlug = gerarSlug(valor)
}

async function enviarDados() {
  errosDados.nome = dados.nome.trim() ? undefined : 'Informe seu nome.'
  errosDados.casaNome = dados.casaNome.trim() ? undefined : 'Informe o nome da casa.'
  errosDados.casaSlug = slugValido(dados.casaSlug) ? undefined : 'Use apenas letras minúsculas, números e hífens.'
  errosDados.termos = dados.termos ? undefined : 'Aceite os termos para continuar.'
  if (errosDados.nome || errosDados.casaNome || errosDados.casaSlug || errosDados.termos) return
  await concluir({
    nome: dados.nome.trim(),
    casa_nome: dados.casaNome.trim(),
    casa_slug: dados.casaSlug.trim(),
    termos_versao: TERMOS_VERSAO
  })
}

async function sair() {
  await supabase.auth.signOut().catch(() => {})
  window.location.assign('/cadastro')
}
</script>

<template>
  <main class="flex min-h-[100dvh] items-center justify-center bg-[#050505] px-4 py-10 text-white">
    <section
      class="w-full max-w-md rounded-3xl border border-amber-400/20 bg-zinc-950/90 p-7 shadow-2xl shadow-black/60 sm:p-9"
    >
      <header class="space-y-3 text-center">
        <NuxtLink to="/" class="text-2xl font-bold tracking-tight text-white">
          {{ PLATAFORMA_NOME }}<span class="text-amber-400">.</span>
        </NuxtLink>
        <h1 class="text-2xl font-bold text-white">Concluir cadastro</h1>
      </header>

      <div v-if="estado === 'verificando' || estado === 'processando'" class="mt-8 flex flex-col items-center gap-3">
        <span class="h-8 w-8 animate-spin rounded-full border-2 border-amber-400/30 border-t-amber-400" />
        <p class="text-sm text-zinc-400">
          {{ estado === 'processando' ? 'Criando sua casa...' : 'Verificando seu acesso...' }}
        </p>
      </div>

      <p
        v-if="mensagem && estado !== 'verificando'"
        role="alert"
        class="mt-6 flex items-start gap-2 rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
      >
        <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
        <span>{{ mensagem }}</span>
      </p>

      <form v-if="estado === 'login'" class="mt-6 space-y-4" novalidate @submit.prevent="entrar">
        <p class="text-sm text-zinc-400">Entre com o e-mail e a senha que você cadastrou.</p>
        <BaseInput v-model="login.email" label="E-mail" type="email" name="email" autocomplete="email" />
        <BaseInput
          v-model="login.senha"
          label="Senha"
          type="password"
          revelar-senha
          name="password"
          autocomplete="current-password"
        />
        <AppButton type="submit" variant="primary" size="lg" block :disabled="ocupado">
          {{ ocupado ? 'Entrando...' : 'Entrar e concluir' }}
        </AppButton>
        <p class="text-center text-xs text-zinc-500">
          Ainda não tem conta?
          <NuxtLink to="/cadastro" class="font-semibold text-amber-400 hover:text-amber-300">Começar grátis</NuxtLink>
        </p>
      </form>

      <form v-else-if="estado === 'dados'" class="mt-6 space-y-4" novalidate @submit.prevent="enviarDados">
        <p class="text-sm text-zinc-400">Confirme os dados da sua casa para continuar.</p>
        <FormField :error="errosDados.nome">
          <BaseInput v-model="dados.nome" label="Seu nome" :invalid="!!errosDados.nome" />
        </FormField>
        <FormField :error="errosDados.casaNome">
          <BaseInput
            :model-value="dados.casaNome"
            label="Nome da casa ou produtora"
            :invalid="!!errosDados.casaNome"
            @update:model-value="aoEditarCasa"
          />
        </FormField>
        <FormField :error="errosDados.casaSlug">
          <BaseInput
            :model-value="dados.casaSlug"
            label="Endereço da sua página"
            :invalid="!!errosDados.casaSlug"
            @update:model-value="aoEditarSlug"
          />
        </FormField>
        <div>
          <label class="flex cursor-pointer items-start gap-3 text-sm text-zinc-300">
            <input
              v-model="dados.termos"
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
          <p v-if="errosDados.termos" class="mt-1.5 text-xs text-red-400">{{ errosDados.termos }}</p>
        </div>
        <AppButton type="submit" variant="primary" size="lg" block>Concluir cadastro</AppButton>
      </form>

      <div v-else-if="estado === 'erro'" class="mt-6 flex flex-col gap-3">
        <AppButton variant="primary" block @click="prosseguir">Tentar novamente</AppButton>
        <AppButton variant="ghost" block @click="sair">Usar outra conta</AppButton>
      </div>
    </section>
  </main>
</template>
