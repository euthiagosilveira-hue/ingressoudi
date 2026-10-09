<script setup lang="ts">
import { onBeforeUnmount, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'

const props = withDefaults(
  defineProps<{
    open: boolean
    title?: string
    subtitle?: string
    size?: 'md' | 'lg' | 'xl'
  }>(),
  { title: '', subtitle: '', size: 'md' }
)

const emit = defineEmits<{
  close: []
}>()

function fechar() {
  emit('close')
}

function aoTeclar(evento: KeyboardEvent) {
  if (evento.key === 'Escape') fechar()
}

watch(
  () => props.open,
  (aberto) => {
    if (typeof document === 'undefined') return
    if (aberto) {
      document.body.style.overflow = 'hidden'
      document.addEventListener('keydown', aoTeclar)
    } else {
      document.body.style.overflow = ''
      document.removeEventListener('keydown', aoTeclar)
    }
  }
)

onBeforeUnmount(() => {
  if (typeof document === 'undefined') return
  document.body.style.overflow = ''
  document.removeEventListener('keydown', aoTeclar)
})
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-200"
      leave-to-class="opacity-0"
    >
      <div
        v-if="props.open"
        class="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:p-4"
        role="dialog"
        aria-modal="true"
        :aria-label="props.title || undefined"
        @click.self="fechar"
      >
        <Transition
          appear
          enter-active-class="transition duration-200 ease-out"
          enter-from-class="translate-y-4 opacity-0 sm:translate-y-0 sm:scale-95"
          leave-active-class="transition duration-150 ease-in"
          leave-to-class="translate-y-4 opacity-0 sm:translate-y-0 sm:scale-95"
        >
          <div
            class="flex max-h-[92vh] w-full flex-col overflow-hidden rounded-t-2xl border border-zinc-800 bg-zinc-900 shadow-2xl shadow-black/50 sm:max-w-lg sm:rounded-2xl"
            :class="
              props.size === 'xl' ? 'sm:max-w-4xl' : props.size === 'lg' ? 'sm:max-w-2xl' : ''
            "
          >
            <header class="flex items-start justify-between gap-4 border-b border-zinc-800 p-5">
              <div class="min-w-0">
                <h2 v-if="props.title" class="truncate text-lg font-semibold text-white">
                  {{ props.title }}
                </h2>
                <p v-if="props.subtitle" class="mt-1 text-sm text-zinc-400">
                  {{ props.subtitle }}
                </p>
              </div>
              <button
                type="button"
                aria-label="Fechar"
                class="-mr-1 -mt-1 flex h-9 w-9 shrink-0 cursor-pointer items-center justify-center rounded-lg text-zinc-400 transition-colors duration-150 hover:bg-zinc-800 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
                @click="fechar"
              >
                <XMarkIcon class="h-5 w-5" />
              </button>
            </header>

            <div class="flex-1 overflow-y-auto p-5">
              <slot />
            </div>

            <footer v-if="$slots.footer" class="border-t border-zinc-800 p-5">
              <slot name="footer" />
            </footer>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>
