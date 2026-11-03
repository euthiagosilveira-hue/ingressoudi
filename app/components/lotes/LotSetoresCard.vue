<script setup lang="ts">
import { ref } from 'vue'
import { CheckIcon, PencilSquareIcon, PlusIcon, TrashIcon, XMarkIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import type { SetorListItem } from '~/types/lote'
import { formatNumero } from '~/utils/format'

const props = defineProps<{
  setores: SetorListItem[]
  processando?: boolean
}>()

const emit = defineEmits<{
  criar: [nome: string]
  renomear: [setorId: string, nome: string]
  excluir: [setorId: string]
}>()

const novoNome = ref('')
const editandoId = ref<string | null>(null)
const nomeEdicao = ref('')

function adicionar() {
  const nome = novoNome.value.trim()
  if (!nome) return
  emit('criar', nome)
  novoNome.value = ''
}

function iniciarEdicao(setor: SetorListItem) {
  editandoId.value = setor.id
  nomeEdicao.value = setor.nome
}

function salvarEdicao() {
  const id = editandoId.value
  const nome = nomeEdicao.value.trim()
  if (!id || !nome) return
  emit('renomear', id, nome)
  editandoId.value = null
}

function podeExcluir(setor: SetorListItem): boolean {
  return props.setores.length > 1 && setor.totalLotes === 0
}
</script>

<template>
  <BaseCard class="space-y-4">
    <div>
      <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">Setores</h3>
      <p class="mt-1 text-sm text-zinc-500">
        Use setores para vender áreas diferentes, como Pista e Camarote. Cada setor tem os próprios lotes e
        aparece separado na página de compra e na portaria.
      </p>
    </div>

    <ul class="divide-y divide-zinc-800 rounded-xl border border-zinc-800">
      <li v-for="setor in props.setores" :key="setor.id" class="flex flex-wrap items-center gap-3 p-3">
        <template v-if="editandoId === setor.id">
          <form class="flex min-w-0 flex-1 items-center gap-2" @submit.prevent="salvarEdicao">
            <div class="min-w-0 flex-1">
              <BaseInput v-model="nomeEdicao" placeholder="Nome do setor" />
            </div>
            <AppButton type="submit" variant="primary" size="sm" :disabled="props.processando" aria-label="Salvar nome">
              <CheckIcon class="h-4 w-4" />
            </AppButton>
            <AppButton variant="ghost" size="sm" aria-label="Cancelar" @click="editandoId = null">
              <XMarkIcon class="h-4 w-4" />
            </AppButton>
          </form>
        </template>

        <template v-else>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-white">{{ setor.nome }}</p>
            <p class="text-xs text-zinc-500">
              {{ setor.totalLotes }} {{ setor.totalLotes === 1 ? 'lote' : 'lotes' }} ·
              {{ formatNumero(setor.quantidade) }} ingressos · {{ formatNumero(setor.vendidos) }} vendidos
            </p>
          </div>
          <div class="flex items-center gap-2">
            <AppButton
              variant="ghost"
              size="sm"
              :disabled="props.processando"
              :aria-label="`Renomear ${setor.nome}`"
              @click="iniciarEdicao(setor)"
            >
              <PencilSquareIcon class="h-4 w-4" />
              Renomear
            </AppButton>
            <AppButton
              v-if="podeExcluir(setor)"
              variant="ghost"
              size="sm"
              :disabled="props.processando"
              :aria-label="`Excluir ${setor.nome}`"
              @click="emit('excluir', setor.id)"
            >
              <TrashIcon class="h-4 w-4" />
            </AppButton>
          </div>
        </template>
      </li>
    </ul>

    <form class="flex flex-col gap-2 sm:flex-row" @submit.prevent="adicionar">
      <div class="min-w-0 flex-1">
        <BaseInput v-model="novoNome" placeholder="Novo setor, ex.: Camarote" />
      </div>
      <AppButton type="submit" variant="outline" :disabled="props.processando || !novoNome.trim()">
        <PlusIcon class="h-4 w-4" />
        Adicionar setor
      </AppButton>
    </form>
  </BaseCard>
</template>
