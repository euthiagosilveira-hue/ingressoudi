<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ArrowsRightLeftIcon, ChatBubbleLeftRightIcon, TrashIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import BaseTextarea from '~/components/BaseTextarea.vue'
import { excluirContatoCrm, obterLeadCrm, registrarContatoCrm } from '~/services/admin/crm'
import {
  CANAIS_CONTATO,
  linhaDoTempo,
  validarContato,
  type CanalContato,
  type DetalheLeadCrm
} from '~/utils/crm'
import { formatDataHoraCompleta, formatDataNumerica } from '~/utils/format'
import { formatarDiaIso } from '~/utils/financeiroPlataforma'

const props = defineProps<{
  produtorId: string
  hoje: string
}>()

const emit = defineEmits<{
  alterado: []
}>()

const detalhe = ref<DetalheLeadCrm | null>(null)
const carregando = ref(false)
const erro = ref('')

const novo = ref<{ data: string; canal: CanalContato; resumo: string }>({ data: props.hoje, canal: 'WHATSAPP', resumo: '' })
const salvando = ref(false)
const erroContato = ref('')

const eventos = computed(() => (detalhe.value ? linhaDoTempo(detalhe.value) : []))
const opcoesCanal = CANAIS_CONTATO.map((c) => ({ value: c.value, label: c.label }))

async function carregar() {
  carregando.value = true
  erro.value = ''
  try {
    detalhe.value = await obterLeadCrm(props.produtorId)
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível carregar o histórico.'
  } finally {
    carregando.value = false
  }
}

async function registrar() {
  erroContato.value = validarContato(novo.value)
  if (erroContato.value) return
  salvando.value = true
  try {
    await registrarContatoCrm(props.produtorId, novo.value)
    novo.value = { data: props.hoje, canal: novo.value.canal, resumo: '' }
    await carregar()
    emit('alterado')
  } catch (e) {
    erroContato.value = e instanceof Error ? e.message : 'Não foi possível registrar o contato.'
  } finally {
    salvando.value = false
  }
}

async function excluir(id: string) {
  erro.value = ''
  try {
    await excluirContatoCrm(id)
    await carregar()
    emit('alterado')
  } catch (e) {
    erro.value = e instanceof Error ? e.message : 'Não foi possível excluir o contato.'
  }
}

watch(() => props.produtorId, () => void carregar())
onMounted(() => void carregar())

defineExpose({ carregar })
</script>

<template>
  <div class="space-y-5">
    <!-- Registrar contato -->
    <form class="space-y-3 rounded-xl border border-zinc-800 bg-zinc-950/60 p-4" @submit.prevent="registrar">
      <h3 class="text-sm font-semibold text-white">Registrar contato</h3>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <BaseInput v-model="novo.data" label="Data" type="date" />
        <BaseSelect v-model="novo.canal" :options="opcoesCanal" label="Canal" />
      </div>
      <BaseTextarea v-model="novo.resumo" label="O que foi conversado" :rows="2" :maxlength="2000" />
      <p v-if="erroContato" role="alert" class="text-sm text-red-300">{{ erroContato }}</p>
      <div class="flex justify-end">
        <AppButton size="sm" variant="primary" type="submit" :disabled="salvando">
          {{ salvando ? 'Salvando...' : 'Registrar contato' }}
        </AppButton>
      </div>
    </form>

    <!-- Linha do tempo -->
    <div>
      <h3 class="text-sm font-semibold text-white">Linha do tempo</h3>
      <p v-if="erro" role="alert" class="mt-2 text-sm text-red-300">{{ erro }}</p>
      <p v-else-if="carregando && !detalhe" class="mt-2 text-sm text-zinc-500">Carregando...</p>
      <p v-else-if="eventos.length === 0" class="mt-2 text-sm text-zinc-500">Nada registrado ainda.</p>
      <ol v-else class="mt-3 space-y-3 border-l border-zinc-800 pl-4">
        <li v-for="ev in eventos" :key="`${ev.tipo}-${ev.id}`" class="relative">
          <span
            class="absolute -left-[1.4rem] top-0.5 flex h-5 w-5 items-center justify-center rounded-full border bg-zinc-900"
            :class="ev.tipo === 'ETAPA' ? 'border-amber-400/50 text-amber-300' : 'border-emerald-400/40 text-emerald-300'"
          >
            <ArrowsRightLeftIcon v-if="ev.tipo === 'ETAPA'" class="h-3 w-3" />
            <ChatBubbleLeftRightIcon v-else class="h-3 w-3" />
          </span>
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-sm text-zinc-100">{{ ev.titulo }}</p>
              <p v-if="ev.detalhe" class="mt-0.5 whitespace-pre-line text-sm text-zinc-400">{{ ev.detalhe }}</p>
              <p class="mt-0.5 text-xs text-zinc-600">
                {{ ev.tipo === 'ETAPA' ? formatDataHoraCompleta(ev.quando) : formatarDiaIso(ev.quando.slice(0, 10)) || formatDataNumerica(ev.quando) }}
                <template v-if="ev.por"> · {{ ev.por }}</template>
              </p>
            </div>
            <button
              v-if="ev.tipo === 'CONTATO'"
              type="button"
              class="shrink-0 rounded p-1 text-zinc-600 hover:bg-zinc-800 hover:text-red-300"
              aria-label="Excluir contato"
              @click="excluir(ev.id)"
            >
              <TrashIcon class="h-4 w-4" />
            </button>
          </div>
        </li>
      </ol>
    </div>
  </div>
</template>
