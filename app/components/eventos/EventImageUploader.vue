<script setup lang="ts">
import { ref } from 'vue'
import { ArrowUpTrayIcon, TrashIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  modelValue: string | null
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string | null]
}>()

const BUCKET = 'eventos-capas'
const TIPOS_ACEITOS = ['image/png', 'image/jpeg', 'image/webp']
const TAMANHO_MAXIMO = 5 * 1024 * 1024

const client = useSupabaseClient()
const { operador } = useOperatorAuth()
const inputRef = ref<HTMLInputElement | null>(null)
const erro = ref('')
const enviando = ref(false)

function abrirSeletor() {
  inputRef.value?.click()
}

function extensao(arquivo: File): string {
  const porTipo: Record<string, string> = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp'
  }
  return porTipo[arquivo.type] ?? 'jpg'
}

async function aoSelecionar(evento: Event) {
  const target = evento.target as HTMLInputElement
  const arquivo = target.files?.[0]
  if (!arquivo) return

  if (!TIPOS_ACEITOS.includes(arquivo.type)) {
    erro.value = 'Formato inválido. Use PNG, JPG ou WEBP.'
    target.value = ''
    return
  }

  if (arquivo.size > TAMANHO_MAXIMO) {
    erro.value = 'A imagem deve ter no máximo 5 MB.'
    target.value = ''
    return
  }

  erro.value = ''
  enviando.value = true
  try {
    // Storage exige a pasta da organizacao ativa: {organizacao_id}/{arquivo}
    const organizacaoId = operador.value?.organizacao?.id
    if (!organizacaoId) throw new Error('SEM_ORGANIZACAO')
    const caminho = `${organizacaoId}/${crypto.randomUUID()}.${extensao(arquivo)}`
    const { error } = await client.storage
      .from(BUCKET)
      .upload(caminho, arquivo, { contentType: arquivo.type, upsert: false })
    if (error) throw error
    const { data } = client.storage.from(BUCKET).getPublicUrl(caminho)
    emit('update:modelValue', data.publicUrl)
  } catch {
    erro.value = 'Não foi possível enviar a imagem. Tente novamente.'
  } finally {
    enviando.value = false
    target.value = ''
  }
}

function remover() {
  erro.value = ''
  if (inputRef.value) inputRef.value.value = ''
  emit('update:modelValue', null)
}
</script>

<template>
  <div class="flex flex-col gap-3 rounded-xl border border-dashed border-zinc-700 bg-zinc-950/50 p-6">
    <input
      ref="inputRef"
      type="file"
      accept="image/png,image/jpeg,image/webp"
      class="hidden"
      @change="aoSelecionar"
    />

    <div class="flex items-center gap-3">
      <span
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border border-amber-400/40 bg-zinc-900 text-amber-400"
      >
        <ArrowUpTrayIcon class="h-5 w-5" />
      </span>
      <div class="min-w-0">
        <p class="text-sm font-medium text-white">
          {{ props.modelValue ? 'Trocar imagem' : 'Enviar imagem' }}
        </p>
        <p class="text-xs text-zinc-500">PNG, JPG ou WEBP</p>
      </div>
    </div>

    <ul class="space-y-1 text-xs text-zinc-500">
      <li>Tamanho máximo: 5 MB</li>
      <li>Imagem recomendada: 1200×628px ou proporção 16:9.</li>
    </ul>

    <p v-if="erro" class="text-xs text-red-400">{{ erro }}</p>
    <p v-else-if="enviando" class="text-xs text-zinc-500">Enviando imagem...</p>

    <div class="mt-auto flex flex-wrap gap-3">
      <AppButton variant="outline" size="sm" :disabled="enviando" @click="abrirSeletor">
        {{ props.modelValue ? 'Trocar imagem' : 'Escolher imagem' }}
      </AppButton>
      <AppButton
        v-if="props.modelValue"
        variant="ghost"
        size="sm"
        :disabled="enviando"
        @click="remover"
      >
        <TrashIcon class="h-4 w-4" />
        Remover
      </AppButton>
    </div>
  </div>
</template>
