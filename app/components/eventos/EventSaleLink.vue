<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { CheckIcon, ClipboardDocumentIcon, LinkIcon } from '@heroicons/vue/24/outline'
import { toast } from 'vue3-toastify'

import { useCopiarLinkEvento } from '~/composables/useCopiarLinkEvento'
import { copiarTexto } from '~/utils/linkEvento'

/** Link de venda (pagina publica) do evento com botao Copiar. */
const props = defineProps<{
  slug: string
}>()

const { linkEvento } = useCopiarLinkEvento()

// Monta o link so no cliente para nao divergir da hidratacao (usa window.location).
const montado = ref(false)
onMounted(() => {
  montado.value = true
})
const link = computed(() => (montado.value && props.slug ? linkEvento(props.slug) : ''))

const copiado = ref(false)
let timer: ReturnType<typeof setTimeout> | null = null

async function copiar() {
  if (!link.value) return
  if (await copiarTexto(link.value)) {
    copiado.value = true
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      copiado.value = false
    }, 2500)
  } else {
    toast.error(`Não foi possível copiar. Copie manualmente: ${link.value}`)
  }
}

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
})
</script>

<template>
  <div v-if="props.slug">
    <p class="text-[11px] font-medium uppercase tracking-wide text-zinc-500">Link de venda</p>
    <div class="mt-1.5 flex items-center gap-2 rounded-lg border border-zinc-800 bg-zinc-950/60 py-1.5 pl-3 pr-1.5">
      <LinkIcon class="h-4 w-4 shrink-0 text-zinc-500" />
      <span class="min-w-0 flex-1 truncate text-sm text-zinc-300" :title="link" data-testid="link-venda">{{ link }}</span>
      <button
        type="button"
        class="inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-md px-2 py-1 text-sm font-medium text-amber-400 transition-colors hover:bg-amber-400/10 hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        :aria-label="copiado ? 'Link copiado' : 'Copiar link de venda'"
        @click.stop="copiar"
      >
        <CheckIcon v-if="copiado" class="h-4 w-4" />
        <ClipboardDocumentIcon v-else class="h-4 w-4" />
        {{ copiado ? 'Copiado' : 'Copiar' }}
      </button>
    </div>
  </div>
</template>
