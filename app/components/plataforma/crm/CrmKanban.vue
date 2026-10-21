<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import Sortable from 'sortablejs'
import {
  ChatBubbleLeftRightIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  ClockIcon,
  EllipsisHorizontalIcon,
  PlusIcon
} from '@heroicons/vue/24/outline'

import {
  ETAPAS_CRM,
  colunasKanban,
  diasNaEtapa,
  leadEsfriando,
  linkWhatsapp,
  ordemEtapa,
  ordenarCartoes,
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
  novo: [etapa: EtapaCrm]
}>()

const colunas = computed(() =>
  colunasKanban(props.produtores).map((c) => ({ ...c, produtores: ordenarCartoes(c.produtores, props.hoje) }))
)
const porId = computed(() => new Map(props.produtores.map((p) => [p.id, p])))

// Rolagem horizontal ----------------------------------------------------------------
const quadro = ref<HTMLElement | null>(null)
const colunaEls = new Map<EtapaCrm, HTMLElement>()
const podeVoltar = ref(false)
const podeAvancar = ref(false)

function atualizarSetas() {
  const el = quadro.value
  if (!el) return
  podeVoltar.value = el.scrollLeft > 4
  podeAvancar.value = el.scrollLeft + el.clientWidth < el.scrollWidth - 4
}

function rolar(direcao: 1 | -1) {
  quadro.value?.scrollBy({ left: direcao * 300, behavior: 'smooth' })
}

function irParaColuna(etapa: EtapaCrm) {
  const el = colunaEls.get(etapa)
  const q = quadro.value
  if (!el || !q) return
  q.scrollTo({ left: el.offsetLeft - q.offsetLeft - 8, behavior: 'smooth' })
}

// Arrastar e soltar (mouse e toque) com SortableJS --------------------------------
// O Sortable move o elemento no DOM; desfazemos o movimento e deixamos o Vue
// redesenhar o cartao na coluna nova a partir do estado (emit 'mover').
const listas = new Map<EtapaCrm, HTMLElement>()
const sortables: Sortable[] = []
const arrastando = ref(false)

function registrarLista(etapa: EtapaCrm, el: unknown) {
  if (el instanceof HTMLElement) listas.set(etapa, el)
}

function registrarColuna(etapa: EtapaCrm, el: unknown) {
  if (el instanceof HTMLElement) colunaEls.set(etapa, el)
}

function criarSortables() {
  for (const [, el] of listas) {
    sortables.push(
      Sortable.create(el, {
        group: 'crm-kanban',
        animation: 150,
        delay: 180,
        delayOnTouchOnly: true,
        filter: '.sem-arrastar',
        preventOnFilter: false,
        ghostClass: 'kanban-fantasma',
        chosenClass: 'kanban-escolhido',
        dragClass: 'kanban-arrastado',
        forceFallback: false,
        scroll: true,
        bubbleScroll: true,
        onStart: () => {
          arrastando.value = true
          menuAberto.value = null
        },
        onEnd: (evt) => {
          arrastando.value = false
          const { item, from, to, oldIndex } = evt
          if (item.parentNode === to) to.removeChild(item)
          from.insertBefore(item, from.children[oldIndex ?? 0] ?? null)
          const p = porId.value.get(item.dataset.id ?? '')
          const destino = to.dataset.etapa as EtapaCrm | undefined
          if (p && destino && destino !== p.etapa) emit('mover', p, destino)
        }
      })
    )
  }
}

onMounted(async () => {
  await nextTick()
  criarSortables()
  atualizarSetas()
  window.addEventListener('resize', atualizarSetas)
  window.addEventListener('resize', fecharMenu)
  document.addEventListener('scroll', fecharMenu, true)
  document.addEventListener('click', fecharMenuFora)
})

onBeforeUnmount(() => {
  for (const s of sortables) s.destroy()
  window.removeEventListener('resize', atualizarSetas)
  window.removeEventListener('resize', fecharMenu)
  document.removeEventListener('scroll', fecharMenu, true)
  document.removeEventListener('click', fecharMenuFora)
})

watch(() => props.produtores.length, () => nextTick(atualizarSetas))

// Menu do cartao ("Mover para") --------------------------------------------------
// Fica fora das colunas (Teleport) para nao ser cortado pela rolagem da coluna.
const menuAberto = ref<string | null>(null)
const menuPos = ref({ top: 0, left: 0 })
const produtorDoMenu = computed(() => (menuAberto.value ? porId.value.get(menuAberto.value) ?? null : null))

function alternarMenu(id: string, evento: MouseEvent) {
  if (menuAberto.value === id) {
    menuAberto.value = null
    return
  }
  const r = (evento.currentTarget as HTMLElement).getBoundingClientRect()
  const largura = 224
  const altura = 330
  menuPos.value = {
    left: Math.max(8, Math.min(r.right - largura, window.innerWidth - largura - 8)),
    top: r.bottom + altura > window.innerHeight ? Math.max(8, r.top - altura) : r.bottom + 4
  }
  menuAberto.value = id
}

function fecharMenu() {
  menuAberto.value = null
}

function fecharMenuFora(evento: MouseEvent) {
  if (!(evento.target as HTMLElement | null)?.closest('[data-menu-cartao]')) menuAberto.value = null
}

function moverPeloMenu(p: ProdutorCrm, etapa: EtapaCrm) {
  menuAberto.value = null
  if (etapa !== p.etapa) emit('mover', p, etapa)
}

function textoDias(p: ProdutorCrm): string {
  const d = diasNaEtapa(p.etapaDesde)
  if (d === null) return ''
  if (d === 0) return 'hoje'
  return d === 1 ? '1 dia' : `${d} dias`
}

function rotuloAcao(p: ProdutorCrm): string {
  const sit = situacaoAcao(p.proximaAcaoEm, props.hoje)
  if (sit === 'ATRASADA') return `Atrasada · ${formatarDiaIso(p.proximaAcaoEm)}`
  if (sit === 'HOJE') return 'Hoje'
  if (sit === 'FUTURA') return formatarDiaIso(p.proximaAcaoEm)
  return ''
}

const corAcao: Record<string, string> = {
  ATRASADA: 'border-red-500/40 bg-red-500/10 text-red-300',
  HOJE: 'border-amber-400/40 bg-amber-400/10 text-amber-300',
  FUTURA: 'border-zinc-700 bg-zinc-800/60 text-zinc-300',
  SEM_DATA: ''
}
</script>

<template>
  <div class="space-y-3">
    <!-- Atalhos para cada coluna -->
    <div class="flex items-center gap-2">
      <button
        type="button"
        class="hidden h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-zinc-700 text-zinc-300 transition-colors hover:bg-zinc-800 disabled:opacity-30 sm:flex"
        :disabled="!podeVoltar"
        aria-label="Ver etapas anteriores"
        @click="rolar(-1)"
      >
        <ChevronLeftIcon class="h-4 w-4" />
      </button>
      <div class="flex min-w-0 flex-1 gap-1.5 overflow-x-auto pb-1">
        <button
          v-for="col in colunas"
          :key="col.etapa"
          type="button"
          class="shrink-0 rounded-full border border-zinc-700 px-2.5 py-1 text-[11px] text-zinc-300 transition-colors hover:border-amber-400/50 hover:text-white"
          @click="irParaColuna(col.etapa)"
        >
          {{ ordemEtapa(col.etapa) }}. {{ col.label }}
          <strong class="ml-0.5 text-white">{{ col.produtores.length }}</strong>
        </button>
      </div>
      <button
        type="button"
        class="hidden h-8 w-8 shrink-0 items-center justify-center rounded-lg border border-zinc-700 text-zinc-300 transition-colors hover:bg-zinc-800 disabled:opacity-30 sm:flex"
        :disabled="!podeAvancar"
        aria-label="Ver próximas etapas"
        @click="rolar(1)"
      >
        <ChevronRightIcon class="h-4 w-4" />
      </button>
    </div>

    <!-- Quadro -->
    <div
      ref="quadro"
      class="kanban-quadro -mx-5 snap-x snap-mandatory overflow-x-auto px-5 pb-3 sm:snap-none"
      @scroll.passive="atualizarSetas"
    >
      <div class="flex gap-3">
        <section
          v-for="col in colunas"
          :key="col.etapa"
          :ref="(el) => registrarColuna(col.etapa, el)"
          class="flex w-[85vw] max-w-[18rem] shrink-0 snap-start flex-col rounded-xl border border-zinc-800 bg-zinc-950/70 sm:w-64"
        >
          <header class="flex items-center gap-2 border-b border-zinc-800 px-3 py-2.5">
            <h3 class="min-w-0 flex-1 truncate text-[11px] font-semibold uppercase tracking-wide text-zinc-300">
              {{ ordemEtapa(col.etapa) }}. {{ col.label }}
            </h3>
            <span class="rounded-full bg-zinc-800 px-2 py-0.5 text-[11px] font-semibold text-zinc-200">
              {{ col.produtores.length }}
            </span>
            <button
              type="button"
              class="flex h-6 w-6 items-center justify-center rounded-md text-zinc-400 transition-colors hover:bg-zinc-800 hover:text-amber-300"
              :aria-label="`Novo lead em ${col.label}`"
              @click="emit('novo', col.etapa)"
            >
              <PlusIcon class="h-4 w-4" />
            </button>
          </header>

          <div class="relative flex-1">
            <ul
              :ref="(el) => registrarLista(col.etapa, el)"
              :data-etapa="col.etapa"
              class="flex max-h-[calc(100dvh-18rem)] min-h-[9rem] flex-col gap-2 overflow-y-auto p-2"
              :class="arrastando ? 'bg-zinc-900/40' : ''"
            >
              <li
                v-for="p in col.produtores"
                :key="p.id"
                :data-id="p.id"
                class="group relative cursor-grab select-none rounded-lg border border-zinc-800 bg-zinc-900 p-3 transition-colors hover:border-zinc-600 active:cursor-grabbing"
                :class="leadEsfriando(p) ? 'border-l-2 border-l-sky-400/70' : ''"
                @click="emit('abrir', p)"
              >
                <div class="flex items-start gap-2">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-semibold text-white">{{ p.nomeProdutor }}</p>
                    <p class="truncate text-xs text-zinc-500">
                      {{ [p.empresaEvento, p.cidade].filter(Boolean).join(' · ') || 'Sem detalhes' }}
                    </p>
                  </div>
                  <div class="sem-arrastar relative shrink-0" data-menu-cartao @click.stop>
                    <button
                      type="button"
                      class="flex h-6 w-6 items-center justify-center rounded-md text-zinc-500 transition-colors hover:bg-zinc-800 hover:text-white"
                      aria-label="Mover para outra etapa"
                      @click="alternarMenu(p.id, $event)"
                    >
                      <EllipsisHorizontalIcon class="h-5 w-5" />
                    </button>
                  </div>
                </div>

                <p v-if="p.proximaAcao" class="mt-2 line-clamp-2 text-xs text-zinc-300">{{ p.proximaAcao }}</p>

                <div class="mt-2 flex flex-wrap items-center gap-1.5 text-[11px]">
                  <span
                    v-if="rotuloAcao(p)"
                    class="rounded-md border px-1.5 py-0.5 font-medium"
                    :class="corAcao[situacaoAcao(p.proximaAcaoEm, hoje)]"
                  >
                    {{ rotuloAcao(p) }}
                  </span>
                  <span
                    class="inline-flex items-center gap-1"
                    :class="leadEsfriando(p) ? 'text-sky-300' : 'text-zinc-500'"
                    :title="`Nesta etapa há ${textoDias(p)}`"
                  >
                    <ClockIcon class="h-3.5 w-3.5" />
                    {{ textoDias(p) }}
                  </span>
                  <span v-if="p.totalContatos > 0" class="inline-flex items-center gap-1 text-zinc-500" title="Contatos registrados">
                    <ChatBubbleLeftRightIcon class="h-3.5 w-3.5" />
                    {{ p.totalContatos }}
                  </span>
                  <a
                    v-if="linkWhatsapp(p.whatsapp)"
                    :href="linkWhatsapp(p.whatsapp)"
                    target="_blank"
                    rel="noopener"
                    class="sem-arrastar ml-auto rounded-md border border-emerald-400/30 px-1.5 py-0.5 font-medium text-emerald-300 hover:bg-emerald-400/10"
                    @click.stop
                  >
                    WhatsApp
                  </a>
                </div>
              </li>
            </ul>
            <p
              v-if="col.produtores.length === 0"
              class="pointer-events-none absolute inset-x-2 top-2 rounded-lg border border-dashed border-zinc-800 px-2 py-6 text-center text-xs text-zinc-600"
            >
              Solte um lead aqui ou toque em +
            </p>
          </div>
        </section>
      </div>
    </div>
    <Teleport to="body">
      <div
        v-if="produtorDoMenu"
        data-menu-cartao
        class="fixed z-[60] w-56 overflow-hidden rounded-lg border border-zinc-700 bg-zinc-900 py-1 shadow-xl shadow-black/60"
        :style="{ top: `${menuPos.top}px`, left: `${menuPos.left}px` }"
      >
        <p class="px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Mover para</p>
        <button
          v-for="e in ETAPAS_CRM"
          :key="e.value"
          type="button"
          class="block w-full px-3 py-1.5 text-left text-xs transition-colors"
          :class="e.value === produtorDoMenu.etapa ? 'text-amber-300' : 'text-zinc-200 hover:bg-zinc-800'"
          @click="moverPeloMenu(produtorDoMenu, e.value)"
        >
          {{ ordemEtapa(e.value) }}. {{ e.label }}
        </button>
      </div>
    </Teleport>

    <p class="text-xs text-zinc-600">
      Arraste o cartão para mudar de etapa (no celular, segure o cartão antes de arrastar) ou use o menu
      <EllipsisHorizontalIcon class="inline h-3.5 w-3.5" />. Toque no cartão para abrir o lead.
    </p>
  </div>
</template>

<style scoped>
.kanban-quadro {
  scrollbar-width: thin;
  scrollbar-color: #3f3f46 transparent;
}
:deep(.kanban-fantasma) {
  opacity: 0.35;
  border-style: dashed;
  border-color: rgb(251 191 36 / 0.6);
}
:deep(.kanban-escolhido) {
  border-color: rgb(251 191 36 / 0.6);
}
:deep(.kanban-arrastado) {
  transform: rotate(2deg);
  box-shadow: 0 12px 24px rgb(0 0 0 / 0.5);
}
</style>
