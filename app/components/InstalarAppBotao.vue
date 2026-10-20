<script setup lang="ts">
import { computed } from 'vue'
import { ArrowDownTrayIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseModal from '~/components/BaseModal.vue'
import { useInstalarApp } from '~/composables/useInstalarApp'
import { passosInstalacao } from '~/utils/instalarApp'

const props = withDefaults(
  defineProps<{
    /** sidebar: item do menu do painel; link: texto simples (rodape); botao: botao com contorno. */
    variante?: 'sidebar' | 'link' | 'botao'
  }>(),
  { variante: 'botao' }
)

const { plataforma, visivel, instalar, instrucoesAbertas } = useInstalarApp()

const passos = computed(() => passosInstalacao(plataforma.value))
</script>

<template>
  <template v-if="visivel">
    <button
      v-if="props.variante === 'sidebar'"
      type="button"
      class="flex w-full cursor-pointer items-center gap-3.5 rounded-lg px-4 py-3 text-sm text-zinc-400 transition-colors duration-150 hover:bg-zinc-800 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/40"
      @click="instalar"
    >
      <ArrowDownTrayIcon class="h-[22px] w-[22px]" />
      <span class="flex-1 text-left">Instalar app</span>
    </button>

    <button
      v-else-if="props.variante === 'link'"
      type="button"
      class="inline-flex cursor-pointer items-center gap-1.5 hover:text-zinc-300"
      @click="instalar"
    >
      <ArrowDownTrayIcon class="h-4 w-4" />
      Instalar app
    </button>

    <AppButton v-else variant="outline" size="sm" @click="instalar">
      <ArrowDownTrayIcon class="h-4 w-4" />
      Instalar app
    </AppButton>
  </template>

  <BaseModal
    :open="instrucoesAbertas"
    title="Instalar o Ingressoudi"
    subtitle="Fica com ícone na tela inicial e abre em tela cheia, como um aplicativo."
    @close="instrucoesAbertas = false"
  >
    <ol class="space-y-4">
      <li v-for="(passo, indice) in passos" :key="passo.titulo" class="flex gap-3">
        <span
          class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-amber-400 text-xs font-bold text-zinc-950"
        >
          {{ indice + 1 }}
        </span>
        <div>
          <p class="text-sm font-semibold text-white">{{ passo.titulo }}</p>
          <p class="mt-0.5 text-sm text-zinc-400">{{ passo.texto }}</p>
        </div>
      </li>
    </ol>

    <template #footer>
      <div class="flex justify-end">
        <AppButton variant="ghost" @click="instrucoesAbertas = false">Entendi</AppButton>
      </div>
    </template>
  </BaseModal>
</template>
