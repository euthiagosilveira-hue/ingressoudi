<script setup lang="ts">
import { computed } from 'vue'
import {
  ArrowUturnLeftIcon,
  ClipboardDocumentListIcon,
  EllipsisHorizontalIcon,
  EyeIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import { useMenuFlutuante } from '~/composables/useMenuFlutuante'
import type { FinancialPaymentStatus } from '~/types/pagamento'

const props = withDefaults(
  defineProps<{
    status: FinancialPaymentStatus
    inline?: boolean
  }>(),
  { inline: false }
)

const emit = defineEmits<{
  action: [action: string]
}>()

const { aberto, raiz, botao, menu, estilo, alternar, fechar } = useMenuFlutuante()

const reembolsado = computed(() => props.status === 'REEMBOLSADO')

function selecionar(action: string) {
  fechar()
  emit('action', action)
}
</script>

<template>
  <div ref="raiz" class="relative flex items-center justify-end gap-2">
    <AppButton
      v-if="props.inline"
      variant="outline"
      size="sm"
      @click.stop="selecionar('detalhes')"
    >
      Ver detalhes
    </AppButton>

    <button
      type="button"
      ref="botao"
      aria-label="Mais ações"
      class="flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-lg border border-zinc-700 text-zinc-400 transition-colors duration-150 hover:border-zinc-600 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
      @click.stop="alternar"
    >
      <EllipsisHorizontalIcon class="h-5 w-5" />
    </button>

    <Teleport to="body">
      <div
        v-if="aberto"
        ref="menu"
        class="fixed z-50 w-52 overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900 p-1 shadow-xl shadow-black/40"
        :style="estilo"
      >
        <button
          type="button"
          class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
          @click.stop="selecionar('detalhes')"
        >
          <EyeIcon class="h-4 w-4 text-zinc-500" />
          Ver detalhes
        </button>
        <button
          type="button"
          class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-zinc-300 transition-colors hover:bg-zinc-800 hover:text-white"
          @click.stop="selecionar('pedido')"
        >
          <ClipboardDocumentListIcon class="h-4 w-4 text-zinc-500" />
          Ver pedido
        </button>

        <template v-if="reembolsado">
          <div class="my-1 h-px bg-zinc-800"></div>
          <button
            type="button"
            class="flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-left text-sm text-violet-300 transition-colors hover:bg-violet-500/10"
            @click.stop="selecionar('reembolso')"
          >
            <ArrowUturnLeftIcon class="h-4 w-4" />
            Ver reembolso
          </button>
        </template>
      </div>
    </Teleport>
  </div>
</template>
