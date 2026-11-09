<script setup lang="ts">
import { onMounted, ref } from 'vue'

import { listarEventosAdmin } from '~/services/admin/eventos'
import type { AdminEventListItem } from '~/types/evento'
import { formatData } from '~/utils/format'

/** Lista de eventos da casa para marcar quais o Socio do Evento acompanha. */
const props = defineProps<{
  modelValue: string[]
  erro?: string
}>()

const emit = defineEmits<{
  'update:modelValue': [ids: string[]]
}>()

const eventos = ref<AdminEventListItem[]>([])
const carregando = ref(true)
const erroCarga = ref('')

onMounted(async () => {
  try {
    eventos.value = await listarEventosAdmin()
  } catch (e) {
    erroCarga.value = e instanceof Error ? e.message : 'Não foi possível carregar os eventos.'
  } finally {
    carregando.value = false
  }
})

function alternar(id: string, marcado: boolean) {
  const atual = new Set(props.modelValue)
  if (marcado) atual.add(id)
  else atual.delete(id)
  emit('update:modelValue', [...atual])
}
</script>

<template>
  <fieldset class="space-y-2">
    <legend class="text-sm font-medium text-zinc-200">
      Eventos que o sócio acompanha <span class="text-amber-400">*</span>
    </legend>
    <p v-if="carregando" class="text-xs text-zinc-500">Carregando eventos...</p>
    <p v-else-if="erroCarga" class="text-xs text-red-400">{{ erroCarga }}</p>
    <p v-else-if="!eventos.length" class="text-xs text-zinc-500">Cadastre um evento antes de convidar um sócio.</p>
    <div v-else class="max-h-56 space-y-1 overflow-y-auto rounded-lg border border-zinc-700 bg-zinc-950 p-2">
      <label
        v-for="evento in eventos"
        :key="evento.eventoId"
        class="flex cursor-pointer items-center gap-3 rounded-md px-2 py-2 text-sm text-zinc-200 hover:bg-zinc-800/60"
      >
        <input
          type="checkbox"
          class="h-4 w-4 shrink-0 accent-amber-400"
          :checked="props.modelValue.includes(evento.eventoId)"
          @change="alternar(evento.eventoId, ($event.target as HTMLInputElement).checked)"
        />
        <span class="min-w-0 flex-1 truncate">{{ evento.nome }}</span>
        <span class="shrink-0 text-xs text-zinc-500">{{ formatData(evento.inicioEm) }}</span>
      </label>
    </div>
    <p v-if="props.erro" class="text-xs text-red-400">{{ props.erro }}</p>
  </fieldset>
</template>
