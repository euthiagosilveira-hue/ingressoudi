<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import {
  ArrowLeftIcon,
  BanknotesIcon,
  EnvelopeIcon,
  ExclamationTriangleIcon,
  EyeIcon,
  EyeSlashIcon,
  LockClosedIcon,
  QrCodeIcon,
  UserGroupIcon
} from '@heroicons/vue/24/outline'

import { AuthError, useOperatorAuth } from '~/composables/useOperatorAuth'
import { mensagemLoginErro, sanitizarRedirect } from '~/utils/auth'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: 'Entrar | Ingressoudi',
  description: 'Acesso restrito ao painel do produtor.'
})

const route = useRoute()
const { login, carregando, logout } = useOperatorAuth()

const form = reactive({ email: '', senha: '' })
const erro = ref('')
const mostrarSenha = ref(false)

// Painel de marca da plataforma (visivel no desktop). Sem marca de casa fixa.
const destaques = [
  { icone: BanknotesIcon, texto: 'Pix direto na conta do produtor' },
  { icone: QrCodeIcon, texto: 'Portaria com QR Code no celular' },
  { icone: UserGroupIcon, texto: 'Lista VIP e venda na porta' }
]

const erroQuery = computed(() => {
  const e = route.query.erro
  return typeof e === 'string' && e ? mensagemLoginErro(e as never) : ''
})

async function entrar() {
  erro.value = ''
  if (!form.email.trim() || !form.senha) {
    erro.value = 'Informe e-mail e senha.'
    return
  }

  try {
    const perfil = await login(form.email, form.senha)
    const destino = sanitizarRedirect(
      typeof route.query.redirect === 'string' ? route.query.redirect : null
    )
    // Honra o redirect apenas se for interno e permitido ao perfil.
    if (destino && (perfil.perfil === 'ADMINISTRADOR' || destino.startsWith('/portaria'))) {
      await navigateTo(destino)
      return
    }
    await navigateTo(perfil.perfil === 'PORTARIA' ? '/portaria' : '/painel')
  } catch (e) {
    erro.value = e instanceof AuthError ? e.message : mensagemLoginErro('ERRO_TEMPORARIO')
    // Garante que uma sessao sem permissao nao permaneca ativa.
    if (e instanceof AuthError && e.code !== 'CREDENCIAIS_INVALIDAS') {
      await logout().catch(() => {})
    }
  }
}
</script>

<template>
  <main
    class="relative flex min-h-[100dvh] w-full overflow-x-hidden bg-[#050505] text-white"
  >
    <!-- Fundo da plataforma: brilho ambar + grade sutil (sem foto de casa) -->
    <div class="absolute inset-0" aria-hidden="true">
      <div
        class="absolute inset-0 bg-[radial-gradient(90%_60%_at_15%_10%,rgba(217,177,56,0.16),transparent_60%)]"
      />
      <div
        class="absolute inset-0 bg-[radial-gradient(70%_50%_at_90%_100%,rgba(217,177,56,0.08),transparent_65%)]"
      />
      <div
        class="absolute inset-0 opacity-[0.07] [background-image:linear-gradient(rgba(255,255,255,0.6)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.6)_1px,transparent_1px)] [background-size:48px_48px] [mask-image:radial-gradient(80%_70%_at_30%_40%,black,transparent)]"
      />
    </div>

    <div class="relative z-10 grid w-full lg:min-h-[100dvh] lg:grid-cols-[55%_45%]">
      <!-- Painel de marca (desktop) -->
      <div class="hidden flex-col justify-center px-16 py-16 lg:flex xl:px-24">
        <p class="text-3xl font-bold tracking-tight text-white">
          Ingressoudi<span class="text-[#D9B138]">.</span>
        </p>
        <h2 class="mt-10 max-w-lg text-4xl font-bold leading-tight text-white xl:text-5xl">
          Venda ingressos com Pix e controle sua portaria em um só lugar.
        </h2>
        <ul class="mt-10 space-y-4">
          <li v-for="item in destaques" :key="item.texto" class="flex items-center gap-3 text-zinc-300">
            <span
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#D9B138]/30 bg-[#D9B138]/10 text-[#D9B138]"
            >
              <component :is="item.icone" class="h-5 w-5" />
            </span>
            {{ item.texto }}
          </li>
        </ul>
      </div>

      <!-- Card -->
      <div
        class="relative flex min-h-[100dvh] items-center justify-center px-5 py-10 sm:px-8 lg:min-h-[100dvh] lg:px-12 lg:py-16"
        style="padding-top: max(2.5rem, env(safe-area-inset-top)); padding-bottom: max(2.5rem, env(safe-area-inset-bottom))"
      >
        <div
          class="pointer-events-none absolute inset-0 hidden bg-[radial-gradient(70%_55%_at_50%_35%,rgba(217,177,56,0.08),transparent_70%)] lg:block"
          aria-hidden="true"
        />

        <section
          class="relative w-full max-w-md rounded-[28px] border border-[#D9B138]/45 bg-[#0b0b0c]/95 p-6 shadow-[0_30px_90px_-25px_rgba(0,0,0,0.95)] ring-1 ring-white/5 backdrop-blur-md sm:p-9 lg:bg-[#0b0b0c]"
        >
          <header class="space-y-2 text-center">
            <p class="text-2xl font-bold tracking-tight text-white lg:hidden">
              Ingressoudi<span class="text-[#D9B138]">.</span>
            </p>
            <h1 class="pt-4 text-3xl lg:pt-0 font-bold tracking-tight text-white">Entrar</h1>
            <p class="text-sm text-zinc-400">Acesse o painel do produtor</p>
          </header>

          <p
            v-if="erroQuery || erro"
            role="alert"
            class="mt-6 flex items-start gap-2 rounded-xl border border-red-500/40 bg-red-500/10 p-3 text-sm text-red-300"
          >
            <ExclamationTriangleIcon class="mt-0.5 h-5 w-5 shrink-0" />
            <span>{{ erro || erroQuery }}</span>
          </p>

          <form class="mt-7 space-y-5" novalidate @submit.prevent="entrar">
            <div class="space-y-2">
              <label
                for="email"
                class="block text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-300"
              >
                E-mail
              </label>
              <div class="relative">
                <EnvelopeIcon
                  class="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-zinc-500"
                />
                <input
                  id="email"
                  v-model="form.email"
                  type="email"
                  name="email"
                  autocomplete="email"
                  required
                  class="w-full rounded-xl border border-zinc-300 bg-zinc-100 py-3.5 pl-12 pr-4 text-sm font-medium text-zinc-900 shadow-inner shadow-black/5 outline-none transition-colors placeholder:text-zinc-500 focus:border-[#D9B138] focus:bg-white focus:ring-2 focus:ring-[#D9B138]/40"
                  placeholder="seu@email.com"
                />
              </div>
            </div>

            <div class="space-y-2">
              <label
                for="senha"
                class="block text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-300"
              >
                Senha
              </label>
              <div class="relative">
                <LockClosedIcon
                  class="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-zinc-500"
                />
                <input
                  id="senha"
                  v-model="form.senha"
                  :type="mostrarSenha ? 'text' : 'password'"
                  name="password"
                  autocomplete="current-password"
                  required
                  class="w-full rounded-xl border border-zinc-300 bg-zinc-100 py-3.5 pl-12 pr-12 text-sm font-medium text-zinc-900 shadow-inner shadow-black/5 outline-none transition-colors placeholder:text-zinc-500 focus:border-[#D9B138] focus:bg-white focus:ring-2 focus:ring-[#D9B138]/40"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  class="absolute right-2 top-1/2 flex h-9 w-9 -translate-y-1/2 cursor-pointer items-center justify-center rounded-lg text-zinc-500 transition-colors hover:text-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#D9B138]/50"
                  :aria-label="mostrarSenha ? 'Ocultar senha' : 'Mostrar senha'"
                  :aria-pressed="mostrarSenha"
                  @click="mostrarSenha = !mostrarSenha"
                >
                  <EyeSlashIcon v-if="mostrarSenha" class="h-5 w-5" />
                  <EyeIcon v-else class="h-5 w-5" />
                </button>
              </div>
            </div>

            <button
              type="submit"
              :disabled="carregando"
              class="inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl bg-[#D9B138] px-6 py-3.5 text-sm font-bold uppercase tracking-[0.14em] text-[#1a1405] shadow-lg shadow-[#D9B138]/25 transition duration-150 hover:bg-[#e6c452] active:bg-[#c9a12f] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#D9B138]/60 disabled:pointer-events-none disabled:opacity-60"
            >
              <span
                v-if="carregando"
                class="h-4 w-4 animate-spin rounded-full border-2 border-[#1a1405]/40 border-t-[#1a1405]"
              />
              {{ carregando ? 'Entrando...' : 'Entrar' }}
            </button>
          </form>

          <p class="mt-6 text-center text-sm text-zinc-400">
            Ainda não vende com a gente?
            <NuxtLink to="/cadastro" class="font-semibold text-[#D9B138] hover:text-[#e6c452]">
              Começar grátis
            </NuxtLink>
          </p>

          <NuxtLink
            to="/eventos-publicos"
            class="mt-5 flex items-center justify-center gap-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500 transition-colors hover:text-[#D9B138] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#D9B138]/50"
          >
            <ArrowLeftIcon class="h-4 w-4" />
            Voltar ao site
          </NuxtLink>
        </section>
      </div>
    </div>
  </main>
</template>
