<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
import { CheckIcon, ClipboardDocumentIcon, LinkIcon } from '@heroicons/vue/24/outline'
import { toast } from 'vue3-toastify'

import { copiarTexto } from '~/utils/linkEvento'

/** Campo com um link publico e botao Copiar (link de venda, vitrine da casa). */
const props = defineProps<{
  rotulo: string
  link: string
  /** Texto do botao para leitores de tela (ex.: "Copiar link de venda"). */
  ariaCopiar: string
}>()

const copiado = ref(false)
let timer: ReturnType<typeof setTimeout> | null = null

async function copiar() {
  if (!props.link) return
  if (await copiarTexto(props.link)) {
    copiado.value = true
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      copiado.value = false
    }, 2500)
  } else {
    toast.error(`Não foi possível copiar. Copie manualmente: ${props.link}`)
  }
}

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
})
</script>

<template>
  <div>
    <p class="text-[11px] font-medium uppercase tracking-wide text-zinc-500">{{ props.rotulo }}</p>
    <div class="mt-1.5 flex items-center gap-2 rounded-lg border border-zinc-800 bg-zinc-950/60 py-1.5 pl-3 pr-1.5">
      <LinkIcon class="h-4 w-4 shrink-0 text-zinc-500" />
      <span class="min-w-0 flex-1 truncate text-sm text-zinc-300" :title="props.link" data-testid="link-copiavel">{{ props.link }}</span>
      <slot name="acoes" />
      <button
        type="button"
        class="inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-md px-2 py-1 text-sm font-medium text-amber-400 transition-colors hover:bg-amber-400/10 hover:text-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        :aria-label="copiado ? 'Link copiado' : props.ariaCopiar"
        @click.stop="copiar"
      >
        <CheckIcon v-if="copiado" class="h-4 w-4" />
        <ClipboardDocumentIcon v-else class="h-4 w-4" />
        {{ copiado ? 'Copiado' : 'Copiar' }}
      </button>
    </div>
  </div>
</template>
