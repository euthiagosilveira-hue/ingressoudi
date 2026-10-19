<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue'
import { CheckIcon, ClipboardDocumentIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import { linkWhatsappConvite } from '~/utils/convite'
import { copiarTexto } from '~/utils/linkEvento'

const props = defineProps<{
  nome: string
  link: string
}>()

const copiado = ref(false)
const falhouCopia = ref(false)
let timer: ReturnType<typeof setTimeout> | null = null

const whatsapp = computed(() => linkWhatsappConvite(props.nome, props.link))

async function copiar() {
  falhouCopia.value = false
  const ok = await copiarTexto(props.link)
  if (!ok) {
    falhouCopia.value = true
    return
  }
  copiado.value = true
  if (timer) clearTimeout(timer)
  timer = setTimeout(() => {
    copiado.value = false
  }, 2500)
}

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer)
})
</script>

<template>
  <div class="space-y-4">
    <p class="text-sm text-zinc-300">
      Envie este link para <span class="font-semibold text-white">{{ props.nome }}</span>. Ao abrir,
      a pessoa cria a própria senha e já entra no painel.
    </p>

    <div class="rounded-xl border border-zinc-800 bg-zinc-950 p-3">
      <p class="break-all font-mono text-xs text-zinc-400" data-testid="link-convite">{{ props.link }}</p>
    </div>

    <p v-if="falhouCopia" class="text-xs text-red-300" role="alert">
      Não foi possível copiar automaticamente. Selecione o link acima e copie manualmente.
    </p>

    <div class="flex flex-col gap-3 sm:flex-row">
      <AppButton variant="primary" block @click="copiar">
        <CheckIcon v-if="copiado" class="h-4 w-4" />
        <ClipboardDocumentIcon v-else class="h-4 w-4" />
        {{ copiado ? 'Link copiado' : 'Copiar link' }}
      </AppButton>
      <a
        :href="whatsapp"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-lg border border-green-500/50 px-4 py-2.5 text-xs font-semibold uppercase tracking-wide text-green-300 transition-colors duration-150 hover:bg-green-500/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-400/50"
      >
        Enviar no WhatsApp
      </a>
    </div>

    <p class="text-xs text-zinc-500">
      O link só pode ser usado uma vez e expira depois de um tempo. Se a pessoa não conseguir
      entrar, gere um novo link na lista de usuários.
    </p>
  </div>
</template>
