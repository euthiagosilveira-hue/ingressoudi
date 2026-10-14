<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  ArrowPathIcon,
  ChartBarIcon,
  EllipsisHorizontalIcon,
  EyeIcon,
  PencilSquareIcon,
  PlayIcon,
  TicketIcon,
  UserGroupIcon,
  XCircleIcon
} from '@heroicons/vue/24/outline'

import { useOperatorAuth } from '~/composables/useOperatorAuth'
import type { EventStatus } from '~/types/evento'

const props = withDefaults(defineProps<{ status?: EventStatus | null }>(), { status: null })

// Modo demonstracao: somente o super admin da plataforma.
const { operador } = useOperatorAuth()
const podeIniciar = computed(() => Boolean(operador.value?.superAdmin) && props.status === 'AGENDADO')
const podeReabrir = computed(() => Boolean(operador.value?.superAdmin) && props.status === 'EM_ANDAMENTO')

const emit = defineEmits<{
  action: [action: string]
}>()

const aberto = ref(false)
const raiz = ref<HTMLElement | null>(null)

function alternar() {
  aberto.value = !aberto.value
}

function fechar() {
  aberto.value = false
}

function selecionar(action: string) {
  fechar()
  emit('action', action)
}

function aoClicarFora(evento: MouseEvent) {
  if (aberto.value && raiz.value && !raiz.value.contains(evento.target as Node)) {
    fechar()
  }
}

onMounted(() => document.addEventListener('click', aoClicarFora))
onBeforeUnmount(() => document.removeEventListener('click', aoClicarFora))
</script>

<template>
  <div ref="raiz" class="relative">
    <button
      type="button"
      aria-label="Mais ações"
      class="flex h-9 w-9 cursor-pointer items-center justify-center rounded-lg border border-zinc-700 text-zinc-400 transition-colors duration-150 hover:border-zinc-600 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click.stop="alternar"
    >
      <EllipsisHorizontalIcon class="h-5 w-5" />
    </button>

    <div
      v-if="aberto"
      class="absolute right-0 z-30 mt-2 w-56 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900 p-1 shadow-xl shadow-black/40"
    >
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('visualizar')"
      >
        <EyeIcon class="h-4 w-4 text-zinc-500" />
        Visualizar página pública
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('dashboard')"
      >
        <ChartBarIcon class="h-4 w-4 text-zinc-500" />
        Ver dashboard
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('lotes')"
      >
        <TicketIcon class="h-4 w-4 text-zinc-500" />
        Gerenciar lotes
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('vip')"
      >
        <UserGroupIcon class="h-4 w-4 text-zinc-500" />
        Lista VIP
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('editar')"
      >
        <PencilSquareIcon class="h-4 w-4 text-zinc-500" />
        Editar evento
      </button>

      <template v-if="podeIniciar || podeReabrir">
        <div class="my-1 h-px bg-zinc-800"></div>
        <p class="px-3 pb-1 pt-2 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Demonstração</p>
        <button
          v-if="podeIniciar"
          type="button"
          class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-amber-300 transition-colors hover:bg-amber-400/10"
          @click.stop="selecionar('iniciar-agora')"
        >
          <PlayIcon class="h-4 w-4" />
          Iniciar evento agora
        </button>
        <button
          v-if="podeReabrir"
          type="button"
          class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-amber-300 transition-colors hover:bg-amber-400/10"
          @click.stop="selecionar('reabrir-vendas')"
        >
          <ArrowPathIcon class="h-4 w-4" />
          Reabrir vendas
        </button>
      </template>

      <div class="my-1 h-px bg-zinc-800"></div>

      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-red-400 transition-colors hover:bg-red-500/10"
        @click.stop="selecionar('cancelar')"
      >
        <XCircleIcon class="h-4 w-4" />
        Cancelar evento
      </button>
    </div>
  </div>
</template>
