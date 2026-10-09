<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { BanknotesIcon, EllipsisHorizontalIcon, EyeIcon, TicketIcon } from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'

const props = withDefaults(
  defineProps<{
    inline?: boolean
  }>(),
  { inline: false }
)

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
  <div ref="raiz" class="relative flex items-center justify-end gap-2">
    <AppButton v-if="props.inline" variant="outline" size="sm" @click.stop="selecionar('ver')">
      Ver pedido
    </AppButton>

    <button
      type="button"
      aria-label="Mais ações"
      class="flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-lg border border-zinc-700 text-zinc-400 transition-colors duration-150 hover:border-zinc-600 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click.stop="alternar"
    >
      <EllipsisHorizontalIcon class="h-5 w-5" />
    </button>

    <div
      v-if="aberto"
      class="absolute right-0 top-full z-30 mt-2 w-52 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900 p-1 shadow-xl shadow-black/40"
    >
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('ver')"
      >
        <EyeIcon class="h-4 w-4 text-zinc-500" />
        Ver pedido
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('ingressos')"
      >
        <TicketIcon class="h-4 w-4 text-zinc-500" />
        Ver ingressos
      </button>
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
        @click.stop="selecionar('pagamento')"
      >
        <BanknotesIcon class="h-4 w-4 text-zinc-500" />
        Ver pagamento
      </button>
    </div>
  </div>
</template>
