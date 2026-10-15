<script setup lang="ts">
import {
  BanknotesIcon,
  DevicePhoneMobileIcon,
  QrCodeIcon,
  UserGroupIcon
} from '@heroicons/vue/24/outline'

import { useOrganizacaoPublica } from '~/composables/useOrganizacaoPublica'
import { PLATAFORMA_NOME } from '~/utils/marca'

definePageMeta({
  layout: 'public-layout',
  // A logo ja aparece em destaque na abertura: sem o topo repetido.
  semCabecalho: true
})

// Pagina geral da plataforma: sem marca de casa no topo.
useOrganizacaoPublica().limpar()

useSeoMeta({
  title: `${PLATAFORMA_NOME} | Venda ingressos com Pix e controle sua portaria`,
  description:
    'Venda ingressos online com Pix direto na sua conta Mercado Pago, controle a entrada com QR Code no celular e gerencie lista VIP e vendas na porta.'
})

const recursos = [
  {
    icone: BanknotesIcon,
    titulo: 'Pix direto na sua conta',
    texto: 'O dinheiro das vendas cai na sua conta Mercado Pago. Você escolhe se repassa a taxa ao comprador ou se absorve.'
  },
  {
    icone: QrCodeIcon,
    titulo: 'Portaria com QR Code',
    texto: 'Cada ingresso tem um QR único. A equipe valida pelo celular e o sistema bloqueia ingresso já utilizado.'
  },
  {
    icone: UserGroupIcon,
    titulo: 'Lista VIP e venda na porta',
    texto: 'Gerencie nomes da lista, registre vendas em dinheiro e acompanhe tudo no mesmo painel.'
  },
  {
    icone: DevicePhoneMobileIcon,
    titulo: 'Sua página de eventos',
    texto: 'Cada casa tem o próprio link para divulgar a agenda e vender online.'
  }
]
</script>

<template>
  <div class="relative isolate overflow-hidden">
    <!-- Brilho dourado da marca (mesmo visual do login) -->
    <div class="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
      <div
        class="absolute inset-0 bg-[radial-gradient(70%_55%_at_15%_0%,rgba(217,177,56,0.28),transparent_62%)]"
      />
      <div
        class="absolute inset-0 bg-[radial-gradient(60%_45%_at_95%_60%,rgba(217,177,56,0.12),transparent_65%)]"
      />
      <div
        class="absolute inset-0 opacity-[0.06] [background-image:linear-gradient(rgba(255,255,255,0.6)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.6)_1px,transparent_1px)] [background-size:48px_48px] [mask-image:radial-gradient(70%_60%_at_25%_20%,black,transparent)]"
      />
    </div>

  <div class="mx-auto w-full max-w-6xl px-4 py-12 sm:px-6 sm:py-20">
    <section class="max-w-3xl">
      <p
        class="text-5xl font-extrabold tracking-tight text-white drop-shadow-[0_0_28px_rgba(217,177,56,0.35)] sm:text-7xl"
      >
        {{ PLATAFORMA_NOME }}<span class="text-[#E8C24A]">.</span>
      </p>
      <p class="mt-8 text-xs font-semibold uppercase tracking-[0.2em] text-amber-400">Para produtores e casas de eventos</p>
      <h1 class="mt-4 text-4xl font-bold leading-tight text-white sm:text-5xl">
        Venda ingressos com Pix e controle sua portaria em um só lugar.
      </h1>
      <p class="mt-5 text-base text-zinc-400 sm:text-lg">
        Chega de comprovante no WhatsApp e lista no papel. O {{ PLATAFORMA_NOME }} vende, confirma o pagamento
        e entrega o ingresso com QR Code automaticamente.
      </p>
      <div class="mt-8 flex flex-wrap gap-3">
        <NuxtLink
          to="/cadastro"
          class="inline-flex items-center justify-center rounded-xl bg-amber-400 px-6 py-3 text-sm font-bold uppercase tracking-wide text-zinc-950 transition-colors hover:bg-amber-300"
        >
          Começar grátis
        </NuxtLink>
        <NuxtLink
          to="/login"
          class="inline-flex items-center justify-center rounded-xl border border-amber-400/60 px-6 py-3 text-sm font-bold uppercase tracking-wide text-amber-400 transition-colors hover:bg-amber-400/10"
        >
          Área do produtor
        </NuxtLink>
        <NuxtLink
          to="/recuperar-ingressos"
          class="inline-flex items-center justify-center rounded-xl border border-zinc-700 px-6 py-3 text-sm font-bold uppercase tracking-wide text-zinc-300 transition-colors hover:border-zinc-500 hover:text-white"
        >
          Já comprei: meus ingressos
        </NuxtLink>
      </div>
      <p class="mt-4 text-sm text-zinc-500">
        Sem mensalidade: você só paga uma taxa por ingresso vendido online.
      </p>
    </section>

    <section class="mt-16 grid grid-cols-1 gap-5 sm:grid-cols-2">
      <div
        v-for="recurso in recursos"
        :key="recurso.titulo"
        class="rounded-2xl border border-zinc-800 bg-zinc-900 p-6"
      >
        <span class="flex h-11 w-11 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-950 text-amber-400">
          <component :is="recurso.icone" class="h-6 w-6" />
        </span>
        <h2 class="mt-4 text-lg font-semibold text-white">{{ recurso.titulo }}</h2>
        <p class="mt-2 text-sm text-zinc-400">{{ recurso.texto }}</p>
      </div>
    </section>
  </div>
  </div>
</template>
