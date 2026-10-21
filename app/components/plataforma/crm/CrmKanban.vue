<script setup lang="ts">
import { computed, ref } from 'vue'
import { ChatBubbleLeftRightIcon, ClockIcon } from '@heroicons/vue/24/outline'

import {
  ETAPAS_CRM,
  colunasKanban,
  diasNaEtapa,
  leadEsfriando,
  ordemEtapa,
  situacaoAcao,
  type EtapaCrm,
  type ProdutorCrm
} from '~/utils/crm'
import { formatarDiaIso } from '~/utils/financeiroPlataforma'

const props = defineProps<{
  produtores: ProdutorCrm[]
  hoje: string
}>()

const emit = defineEmits<{
  abrir: [produtor: ProdutorCrm]
  mover: [produtor: ProdutorCrm, etapa: EtapaCrm]
}>()

const colunas = computed(() => colunasKanban(props.produtores))

// Arrastar e soltar (computador). No celular, o seletor "Mover para" do cartao.
const arrastando = ref<ProdutorCrm | null>(null)
const colunaAlvo = ref<EtapaCrm | null>(null)

function aoArrastar(evento: DragEvent, p: ProdutorCrm) {
  arrastando.value = p
  evento.dataTransfer?.setData('text/plain', p.id)
  if (evento.dataTransfer) evento.dataTransfer.effectAllowed = 'move'
}

function aoSoltar(etapa: EtapaCrm) {
  const p = arrastando.value
  arrastando.value = null
  colunaAlvo.value = null
  if (p && p.etapa !== etapa) emit('mover', p, etapa)
}

function aoEscolher(evento: Event, p: ProdutorCrm) {
  const alvo = evento.target as HTMLSelectElement
  const etapa = alvo.value as EtapaCrm
  alvo.value = ''
  if (etapa && etapa !== p.etapa) emit('mover', p, etapa)
}

function textoDias(p: ProdutorCrm): string {
  const d = diasNaEtapa(p.etapaDesde)
  if (d === null) return ''
  if (d === 0) return 'Nesta etapa desde hoje'
  return d === 1 ? 'Há 1 dia nesta etapa' : `Há ${d} dias nesta etapa`
}

const corAcao: Record<string, string> = {
  ATRASADA: 'text-red-300',
  HOJE: 'text-amber-300',
  FUTURA: 'text-zinc-400',
  SEM_DATA: 'text-zinc-600'
}
</script>

<template>
  <div class="-mx-4 overflow-x-auto px-4 pb-2 sm:mx-0 sm:px-0">
    <div class="flex min-w-max gap-3">
      <section
        v-for="col in colunas"
        :key="col.etapa"
        class="flex w-72 shrink-0 flex-col rounded-xl border bg-zinc-950/60 transition-colors"
        :class="colunaAlvo === col.etapa ? 'border-amber-400/60 bg-amber-400/5' : 'border-zinc-800'"
        @dragover.prevent="colunaAlvo = col.etapa"
        @dragleave="colunaAlvo = colunaAlvo === col.etapa ? null : colunaAlvo"
        @drop.prevent="aoSoltar(col.etapa)"
      >
        <header class="flex items-center justify-between gap-2 border-b border-zinc-800 px-3 py-2.5">
          <h3 class="truncate text-xs font-semibold uppercase tracking-wide text-zinc-300">
            {{ ordemEtapa(col.etapa) }}. {{ col.label }}
          </h3>
          <span class="rounded-full bg-zinc-800 px-2 py-0.5 text-[11px] font-semibold text-zinc-300">
            {{ col.produtores.length }}
          </span>
        </header>

        <ul class="flex min-h-[6rem] flex-col gap-2 p-2">
          <li
            v-for="p in col.produtores"
            :key="p.id"
            draggable="true"
            class="cursor-grab rounded-lg border border-zinc-800 bg-zinc-900 p-3 shadow-sm transition-colors hover:border-zinc-600 active:cursor-grabbing"
            :class="arrastando?.id === p.id ? 'opacity-50' : ''"
            @dragstart="aoArrastar($event, p)"
            @dragend="arrastando = null; colunaAlvo = null"
          >
            <button type="button" class="block w-full text-left" @click="emit('abrir', p)">
              <p class="truncate text-sm font-semibold text-white">{{ p.nomeProdutor }}</p>
              <p class="truncate text-xs text-zinc-500">
                {{ [p.empresaEvento, p.cidade].filter(Boolean).join(' · ') || 'Sem detalhes' }}
              </p>
              <p v-if="p.proximaAcao || p.proximaAcaoEm" class="mt-2 line-clamp-2 text-xs" :class="corAcao[situacaoAcao(p.proximaAcaoEm, hoje)]">
                {{ p.proximaAcao || 'Próxima ação' }}<template v-if="p.proximaAcaoEm"> · {{ formatarDiaIso(p.proximaAcaoEm) }}</template>
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px]">
                <span class="inline-flex items-center gap-1" :class="leadEsfriando(p) ? 'text-sky-300' : 'text-zinc-500'">
                  <ClockIcon class="h-3.5 w-3.5" />
                  {{ textoDias(p) }}
                </span>
                <span v-if="p.totalContatos > 0" class="inline-flex items-center gap-1 text-zinc-500">
                  <ChatBubbleLeftRightIcon class="h-3.5 w-3.5" />
                  {{ p.totalContatos }}
                </span>
              </div>
            </button>
            <select
              class="mt-2 w-full rounded-md border border-zinc-700 bg-zinc-950 px-2 py-1.5 text-xs text-zinc-300 focus:border-amber-400 focus:outline-none"
              aria-label="Mover para outra etapa"
              @change="aoEscolher($event, p)"
            >
              <option value="">Mover para...</option>
              <option v-for="e in ETAPAS_CRM.filter((x) => x.value !== p.etapa)" :key="e.value" :value="e.value">
                {{ ordemEtapa(e.value) }}. {{ e.label }}
              </option>
            </select>
          </li>
          <li v-if="col.produtores.length === 0" class="px-2 py-4 text-center text-xs text-zinc-600">
            Arraste um lead para cá
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
