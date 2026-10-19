<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ExclamationTriangleIcon, LockClosedIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import {
  destinoAposConvite,
  extrairErroConvite,
  lerTokenConvite,
  mensagemErroConviteLink,
  validarSenhaConvite,
  type TokenConvite
} from '~/utils/convite'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: 'Definir senha | Ingressoudi',
  description: 'Conclua o seu convite definindo uma senha de acesso.'
})

const supabase = useSupabaseClient()
const { carregarOperador } = useOperatorAuth()

const estado = ref<'verificando' | 'aceitar' | 'pronto' | 'erro'>('verificando')
const mensagem = ref('')
const salvando = ref(false)
const aceitando = ref(false)
const token = ref<TokenConvite | null>(null)
const form = reactive({ senha: '', confirmacao: '' })
const erros = reactive<{ senha?: string; confirmacao?: string }>({})

function falhar(texto: string) {
  mensagem.value = texto
  estado.value = 'erro'
}

async function irParaDestino(uid: string) {
  const perfil = await carregarOperador(uid).catch(() => null)
  await navigateTo(destinoAposConvite(perfil?.perfil ?? null))
}

onMounted(async () => {
  const search = window.location.search
  const hash = window.location.hash

  const erroLink = extrairErroConvite(search, hash)
  if (erroLink) {
    falhar(mensagemErroConviteLink(erroLink))
    return
  }

  // Link gerado pelo painel (?token_hash=...): o token so e usado depois do
  // clique em "Aceitar convite". Assim a pre-visualizacao do link no WhatsApp
  // ou no e-mail nao consome o convite.
  token.value = lerTokenConvite(search)
  if (token.value) {
    estado.value = 'aceitar'
    return
  }

  // Fluxo PKCE (?code=...)
  const code = new URLSearchParams(search.replace(/^\?/, '')).get('code')
  if (code) {
    await supabase.auth.exchangeCodeForSession(code).catch(() => {})
  }

  // Fluxo implicito (#access_token=...&type=invite)
  const hashParams = new URLSearchParams(hash.replace(/^#/, ''))
  const accessToken = hashParams.get('access_token')
  const refreshToken = hashParams.get('refresh_token')
  if (accessToken && refreshToken) {
    await supabase.auth
      .setSession({ access_token: accessToken, refresh_token: refreshToken })
      .catch(() => {})
  }

  // Aguarda a sessao do convite ser reconhecida.
  for (let tentativa = 0; tentativa < 10; tentativa += 1) {
    const { data } = await supabase.auth.getSession()
    if (data.session?.user?.id) {
      estado.value = 'pronto'
      return
    }
    await new Promise((resolver) => setTimeout(resolver, 200))
  }

  falhar(mensagemErroConviteLink(null))
})

async function aceitarConvite() {
  if (!token.value || aceitando.value) return
  aceitando.value = true
  try {
    const { data, error } = await supabase.auth.verifyOtp({
      token_hash: token.value.tokenHash,
      type: token.value.tipo
    })
    if (error || !data?.session) {
      falhar(mensagemErroConviteLink(null))
      return
    }
    // remove o token da barra de enderecos (ja foi usado)
    window.history.replaceState(null, '', window.location.pathname)
    estado.value = 'pronto'
  } catch {
    falhar(mensagemErroConviteLink(null))
  } finally {
    aceitando.value = false
  }
}

async function definirSenha() {
  erros.senha = undefined
  erros.confirmacao = undefined
  const validacao = validarSenhaConvite(form.senha, form.confirmacao)
  if (validacao.senha) erros.senha = validacao.senha
  if (validacao.confirmacao) erros.confirmacao = validacao.confirmacao
  if (validacao.senha || validacao.confirmacao) return

  salvando.value = true
  try {
    const { data, error } = await supabase.auth.updateUser({ password: form.senha })
    if (error || !data?.user) {
      falhar('Não foi possível definir a senha. Tente novamente ou solicite um novo convite.')
      return
    }
    await irParaDestino(data.user.id)
  } catch {
    falhar('Não foi possível definir a senha. Tente novamente ou solicite um novo convite.')
  } finally {
    salvando.value = false
  }
}
</script>

<template>
  <main
    class="flex min-h-[100dvh] items-center justify-center bg-[#050505] px-4 py-10 text-white"
  >
    <section
      class="w-full max-w-md rounded-3xl border border-amber-400/20 bg-zinc-950/90 p-7 shadow-2xl shadow-black/60 backdrop-blur-md sm:p-9"
    >
      <header class="space-y-3 text-center">
        <p class="text-2xl font-bold tracking-tight text-white">Ingressoudi<span class="text-amber-400">.</span></p>
        <h1 class="text-2xl font-bold text-white">
          {{ estado === 'aceitar' ? 'Você foi convidado' : 'Definir senha' }}
        </h1>
        <p class="text-sm text-zinc-400">
          {{
            estado === 'aceitar'
              ? 'Aceite o convite e crie sua senha para acessar o painel.'
              : 'Conclua o seu convite para acessar o painel.'
          }}
        </p>
      </header>

      <div
        v-if="estado === 'verificando'"
        class="mt-8 flex flex-col items-center gap-3"
        role="status"
        aria-live="polite"
      >
        <span
          class="h-8 w-8 animate-spin rounded-full border-2 border-amber-400/30 border-t-amber-400"
        ></span>
        <p class="text-sm text-zinc-400">Verificando o seu convite…</p>
      </div>

      <div v-else-if="estado === 'aceitar'" class="mt-8">
        <AppButton variant="primary" block size="lg" :disabled="aceitando" @click="aceitarConvite">
          {{ aceitando ? 'Verificando…' : 'Aceitar convite' }}
        </AppButton>
      </div>

      <div v-else-if="estado === 'erro'" class="mt-8 space-y-5" role="alert">
        <div
          class="flex items-start gap-2 rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
        >
          <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
          <span>{{ mensagem }}</span>
        </div>
        <AppButton variant="primary" block to="/login">Ir para o login</AppButton>
      </div>

      <form v-else class="mt-8 space-y-5" novalidate @submit.prevent="definirSenha">
        <FormField label="Nova senha" required :error="erros.senha">
          <div class="relative">
            <LockClosedIcon
              class="pointer-events-none absolute left-4 top-1/2 z-10 h-5 w-5 -translate-y-1/2 text-zinc-500"
            />
            <BaseInput
              v-model="form.senha"
              type="password"
              autocomplete="new-password"
              placeholder="Mínimo 8 caracteres"
            />
          </div>
        </FormField>

        <FormField label="Confirmar senha" required :error="erros.confirmacao">
          <BaseInput
            v-model="form.confirmacao"
            type="password"
            autocomplete="new-password"
            placeholder="Repita a senha"
          />
        </FormField>

        <AppButton type="submit" variant="primary" block size="lg" :disabled="salvando">
          {{ salvando ? 'Salvando…' : 'Definir senha e entrar' }}
        </AppButton>
      </form>
    </section>
  </main>
</template>
