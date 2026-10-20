<script setup lang="ts">
import { onMounted } from 'vue'

import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { lerPedidosSalvos } from '~/utils/ingressosSalvos'
import { destinoAoAbrirApp } from '~/utils/instalarApp'

// Porta de entrada do app instalado (start_url do manifesto). "app" ja e um
// slug reservado, entao nao conflita com a pagina de nenhuma organizacao.
definePageMeta({
  layout: false
})

useSeoMeta({
  title: 'Ingressoudi',
  robots: 'noindex'
})

const supabase = useSupabaseClient()
const { carregarOperador } = useOperatorAuth()

onMounted(async () => {
  let perfil: string | null = null
  let ativo: boolean | null = null
  try {
    const { data } = await supabase.auth.getSession()
    const uid = data.session?.user?.id
    if (uid) {
      const operador = await carregarOperador(uid)
      perfil = operador?.perfil ?? null
      ativo = operador?.ativo ?? null
    }
  } catch {
    // sem sessao valida: segue como comprador
  }

  const destino = destinoAoAbrirApp({
    perfil,
    ativo,
    temIngressosSalvos: lerPedidosSalvos().length > 0
  })
  await navigateTo(destino, { replace: true })
})
</script>

<template>
  <main class="flex min-h-[100dvh] flex-col items-center justify-center gap-5 bg-[#050505] text-white">
    <p class="text-3xl font-bold tracking-tight">Ingressoudi<span class="text-amber-400">.</span></p>
    <span
      class="h-7 w-7 animate-spin rounded-full border-2 border-amber-400/30 border-t-amber-400"
      role="status"
      aria-label="Abrindo"
    ></span>
  </main>
</template>
