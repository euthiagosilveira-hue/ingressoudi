<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ArrowTopRightOnSquareIcon } from '@heroicons/vue/24/outline'

import CopyLinkField from '~/components/CopyLinkField.vue'
import { useOperatorAuth } from '~/composables/useOperatorAuth'
import { rotaOrganizacao } from '~/utils/rotasPublicas'
import { urlVitrine } from '~/utils/vitrine'

/** Link da pagina publica com todos os eventos publicados da casa ativa. */
const { operador } = useOperatorAuth()
const config = useRuntimeConfig()

const slug = computed(() => operador.value?.organizacao?.slug ?? '')

// So no cliente: usa window.location e evita divergencia na hidratacao.
const montado = ref(false)
onMounted(() => {
  montado.value = true
})
const link = computed(() => {
  if (!montado.value || !slug.value) return ''
  const origem = typeof window !== 'undefined' ? window.location.origin : String(config.public.siteUrl || '')
  return urlVitrine(origem, slug.value)
})
</script>

<template>
  <div v-if="slug" class="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-4">
    <CopyLinkField rotulo="Página com todos os seus eventos" :link="link" aria-copiar="Copiar link da página de eventos">
      <template #acoes>
        <a
          :href="rotaOrganizacao(slug)"
          target="_blank"
          rel="noopener"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-md px-2 py-1 text-sm font-medium text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
          aria-label="Abrir página de eventos"
        >
          <ArrowTopRightOnSquareIcon class="h-4 w-4" />
          <span class="hidden sm:inline">Abrir</span>
        </a>
      </template>
    </CopyLinkField>
    <p class="mt-2 text-xs text-zinc-500">
      Mostra só os eventos publicados e futuros. Divulgue na bio do Instagram e no WhatsApp.
    </p>
  </div>
</template>
