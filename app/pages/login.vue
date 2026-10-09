<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import {
  ArrowLeftIcon,
  EnvelopeIcon,
  ExclamationTriangleIcon,
  EyeIcon,
  EyeSlashIcon,
  LockClosedIcon
} from '@heroicons/vue/24/outline'

import { AuthError, useOperatorAuth } from '~/composables/useOperatorAuth'
import { mensagemLoginErro, sanitizarRedirect } from '~/utils/auth'

definePageMeta({
  layout: false
})

useSeoMeta({
  title: 'Entrar | GZ1 Ingresso',
  description: 'Acesso restrito ao painel da Galeria Zero 1.'
})

const route = useRoute()
const { login, carregando, logout } = useOperatorAuth()

const form = reactive({ email: '', senha: '' })
const erro = ref('')
const mostrarSenha = ref(false)
const fotoOk = ref(true)

/**
 * Foto real da fachada (public/galeria-fachada.webp — WebP otimizado).
 * Referenciada dinamicamente; ha fallback grafico se a imagem faltar.
 */
const fotoSrc = '/galeria-fachada.webp'

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
    await navigateTo(perfil.perfil === 'PORTARIA' ? '/portaria' : '/')
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
    <!-- Fotografia da fachada em tela cheia, atras do formulario -->
    <div class="absolute inset-0" aria-hidden="true">
      <img
        v-if="fotoOk"
        :src="fotoSrc"
        alt=""
        fetchpriority="high"
        loading="eager"
        decoding="async"
        class="h-full w-full object-cover object-[42%_45%] md:object-contain md:object-center"
        @error="fotoOk = false"
      />
      <!-- Overlay leve: mantem o brilho da placa e da fachada -->
      <div class="absolute inset-0 bg-black/30" />
      <div class="absolute inset-0 bg-gradient-to-b from-black/45 via-black/15 to-black/60" />
      <div
        class="absolute inset-0 bg-[radial-gradient(120%_70%_at_50%_0%,rgba(217,177,56,0.10),transparent_60%)]"
      />
    </div>

    <!-- Conteudo: card sobre a fotografia -->
    <div class="relative z-10 grid w-full lg:min-h-[100dvh] lg:grid-cols-[55%_45%]">
      <div class="hidden lg:block" />

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
            <img
              src="/Logo horizontal.png"
              alt="Galeria Zero 1"
              class="mx-auto h-12 w-auto sm:h-14"
            />
            <h1 class="pt-4 text-3xl font-bold tracking-tight text-white">Entrar</h1>
            <p class="text-sm text-zinc-400">Acesse o painel da Galeria Zero 1</p>
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

          <NuxtLink
            to="/eventos-publicos"
            class="mt-7 flex items-center justify-center gap-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-zinc-500 transition-colors hover:text-[#D9B138] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#D9B138]/50"
          >
            <ArrowLeftIcon class="h-4 w-4" />
            Voltar ao site
          </NuxtLink>
        </section>
      </div>
    </div>
  </main>
</template>
