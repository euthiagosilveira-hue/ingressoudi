<script setup lang="ts">
import { computed, ref } from 'vue'
import { EyeIcon, EyeSlashIcon } from '@heroicons/vue/24/outline'

const props = withDefaults(
  defineProps<{
    modelValue: string | number
    label?: string
    type?: string
    placeholder?: string
    name?: string
    id?: string
    disabled?: boolean
    required?: boolean
    autocomplete?: string
    invalid?: boolean
    prefix?: string
    /** Em campos de senha, mostra o botao de olho para exibir/ocultar o texto. */
    revelarSenha?: boolean
  }>(),
  {
    label: '',
    type: 'text',
    placeholder: '',
    name: '',
    id: '',
    disabled: false,
    required: false,
    autocomplete: 'off',
    invalid: false,
    prefix: '',
    revelarSenha: false
  }
)

const emit = defineEmits<{
  'update:modelValue': [value: string]
  blur: []
  focus: []
}>()

const value = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val)
})

const senhaVisivel = ref(false)
const comOlho = computed(() => props.revelarSenha && props.type === 'password')
const tipoEfetivo = computed(() => (comOlho.value && senhaVisivel.value ? 'text' : props.type))

const inputClasses = computed(() => [
  'w-full rounded-lg border bg-zinc-900 px-3.5 py-2.5 text-sm text-white placeholder-zinc-500 transition-colors focus:outline-none focus:ring-2 disabled:cursor-not-allowed disabled:opacity-50',
  props.invalid
    ? 'border-red-500/60 focus:border-red-500 focus:ring-red-500/30'
    : 'border-zinc-700 focus:border-amber-400/60 focus:ring-amber-400/30',
  props.type === 'date' || props.type === 'time' ? '[color-scheme:dark] accent-amber-400' : ''
])
</script>

<template>
  <label class="block">
    <span v-if="label" class="mb-1.5 block text-sm font-medium text-zinc-300">
      {{ label }}
    </span>
    <div class="relative">
      <span
        v-if="prefix"
        class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-zinc-500"
      >
        {{ prefix }}
      </span>
      <input
        :id="id || name"
        :type="tipoEfetivo"
        :name="name"
        :placeholder="placeholder"
        :disabled="disabled"
        :required="required"
        :autocomplete="autocomplete"
        :aria-invalid="invalid || undefined"
        v-model="value"
        :class="[inputClasses, prefix ? 'pl-10' : '', comOlho ? 'pr-11' : '']"
        @blur="emit('blur')"
        @focus="emit('focus')"
      />
      <button
        v-if="comOlho"
        type="button"
        class="absolute right-1.5 top-1/2 flex h-8 w-8 -translate-y-1/2 cursor-pointer items-center justify-center rounded-md text-zinc-400 transition-colors hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50"
        :aria-label="senhaVisivel ? 'Ocultar senha' : 'Mostrar senha'"
        :aria-pressed="senhaVisivel"
        @click="senhaVisivel = !senhaVisivel"
      >
        <EyeSlashIcon v-if="senhaVisivel" class="h-5 w-5" />
        <EyeIcon v-else class="h-5 w-5" />
      </button>
    </div>
  </label>
</template>
