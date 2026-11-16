<script setup lang="ts">
import BaseInput from '~/components/BaseInput.vue'
import FormField from '~/components/FormField.vue'
import {
  formatarDocumento,
  formatarTelefone,
  rotuloResponsavel,
  type DadosOrganizador,
  type ErrosOrganizador,
  type TipoDocumento
} from '~/utils/documento'

/** Campos do organizador: CPF ou CNPJ, nome/razao social e telefone. */
const dados = defineModel<DadosOrganizador>({ required: true })
defineProps<{ erros?: ErrosOrganizador }>()

function escolherTipo(tipo: TipoDocumento) {
  if (dados.value.tipoDocumento === tipo) return
  dados.value = { ...dados.value, tipoDocumento: tipo, documento: '' }
}
function aoDigitarDocumento(valor: string) {
  dados.value = { ...dados.value, documento: formatarDocumento(dados.value.tipoDocumento, valor) }
}
function aoDigitarTelefone(valor: string) {
  dados.value = { ...dados.value, telefone: formatarTelefone(valor) }
}
function aoDigitarNome(valor: string) {
  dados.value = { ...dados.value, responsavelNome: valor }
}
</script>

<template>
  <div class="space-y-4">
    <div>
      <p class="mb-2 text-sm text-zinc-300">Você vende como</p>
      <div class="grid grid-cols-2 gap-2" role="radiogroup" aria-label="Tipo de documento">
        <button
          v-for="opcao in [
            { tipo: 'CPF', titulo: 'Pessoa física', sub: 'CPF' },
            { tipo: 'CNPJ', titulo: 'Empresa', sub: 'CNPJ' }
          ] as const"
          :key="opcao.tipo"
          type="button"
          role="radio"
          :aria-checked="dados.tipoDocumento === opcao.tipo"
          class="rounded-xl border px-3 py-2.5 text-left transition-colors"
          :class="
            dados.tipoDocumento === opcao.tipo
              ? 'border-amber-400/70 bg-amber-400/10 text-white'
              : 'border-zinc-700 bg-zinc-900 text-zinc-400 hover:border-zinc-500'
          "
          @click="escolherTipo(opcao.tipo)"
        >
          <span class="block text-sm font-semibold">{{ opcao.titulo }}</span>
          <span class="block text-xs text-zinc-500">{{ opcao.sub }}</span>
        </button>
      </div>
    </div>

    <FormField :error="erros?.documento">
      <BaseInput
        :model-value="dados.documento"
        :label="dados.tipoDocumento"
        name="documento"
        :placeholder="dados.tipoDocumento === 'CNPJ' ? '00.000.000/0000-00' : '000.000.000-00'"
        :invalid="!!erros?.documento"
        inputmode="numeric"
        @update:model-value="aoDigitarDocumento"
      />
    </FormField>

    <FormField :error="erros?.responsavelNome">
      <BaseInput
        :model-value="dados.responsavelNome"
        :label="rotuloResponsavel(dados.tipoDocumento)"
        name="responsavel"
        :autocomplete="dados.tipoDocumento === 'CPF' ? 'name' : 'organization'"
        :invalid="!!erros?.responsavelNome"
        @update:model-value="aoDigitarNome"
      />
    </FormField>

    <FormField :error="erros?.telefone">
      <BaseInput
        :model-value="dados.telefone"
        label="Telefone / WhatsApp"
        type="tel"
        name="telefone"
        autocomplete="tel-national"
        placeholder="(00) 00000-0000"
        :invalid="!!erros?.telefone"
        @update:model-value="aoDigitarTelefone"
      />
    </FormField>
  </div>
</template>
