<script setup lang="ts">
import { computed } from 'vue'

import BaseCard from '~/components/BaseCard.vue'
import BaseInput from '~/components/BaseInput.vue'
import BaseSelect from '~/components/BaseSelect.vue'
import FormField from '~/components/FormField.vue'
import { formatMoeda } from '~/utils/format'
import type { LotFormErrors, LotFormValue, SetorListItem } from '~/types/lote'
import type { SelectOption } from '~/types/ui'

const props = withDefaults(
  defineProps<{
    value: LotFormValue
    errors: LotFormErrors
    ordemBloqueada?: boolean
    /** Setores do evento: o campo so aparece quando ha mais de um. */
    setores?: SetorListItem[]
    setorBloqueado?: boolean
  }>(),
  { ordemBloqueada: false, setores: () => [], setorBloqueado: false }
)

const setorOptions = computed<SelectOption[]>(() =>
  props.setores.map((setor) => ({ value: setor.id, label: setor.nome }))
)
const nomeSetorAtual = computed(
  () => props.setores.find((setor) => setor.id === props.value.setorId)?.nome ?? ''
)

type CampoNumerico = 'ordem' | 'quantidade' | 'preco'

function atribuirNumero(campo: CampoNumerico, entrada: string) {
  if (entrada === '') {
    props.value[campo] = null
    return
  }
  const numero = Number(entrada)
  props.value[campo] = Number.isNaN(numero) ? null : numero
}
</script>

<template>
  <BaseCard class="space-y-5">
    <h3 class="text-sm font-semibold uppercase tracking-[0.15em] text-zinc-400">
      Dados do lote
    </h3>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <FormField
        v-if="props.setores.length > 1"
        label="Setor"
        required
        :hint="props.setorBloqueado ? 'O setor não muda depois que o lote é criado.' : 'Área do evento vendida neste lote.'"
        class="sm:col-span-2"
      >
        <BaseInput v-if="props.setorBloqueado" :model-value="nomeSetorAtual" disabled />
        <BaseSelect v-else v-model="value.setorId" :options="setorOptions" />
      </FormField>

      <FormField label="Nome do lote" required :error="errors.nome" class="sm:col-span-2">
        <BaseInput
          v-model="value.nome"
          placeholder="Ex.: Lote 1"
          :invalid="!!errors.nome"
        />
      </FormField>

      <FormField
        label="Ordem"
        required
        :error="errors.ordem"
        hint="Define a sequência comercial dos lotes."
      >
        <BaseInput
          :model-value="value.ordem"
          type="number"
          min="1"
          step="1"
          placeholder="1"
          :disabled="props.ordemBloqueada"
          :invalid="!!errors.ordem"
          @update:model-value="(entrada) => atribuirNumero('ordem', entrada)"
        />
      </FormField>

      <FormField
        label="Quantidade"
        required
        :error="errors.quantidade"
        hint="Quantidade máxima de ingressos vendidos neste preço."
      >
        <BaseInput
          :model-value="value.quantidade"
          type="number"
          min="1"
          step="1"
          placeholder="100"
          :invalid="!!errors.quantidade"
          @update:model-value="(entrada) => atribuirNumero('quantidade', entrada)"
        />
      </FormField>

      <FormField
        label="Preço"
        required
        :error="errors.preco"
        :hint="value.preco !== null ? formatMoeda(value.preco) : 'Valor unitário do ingresso neste lote.'"
        class="sm:col-span-2"
      >
        <BaseInput
          :model-value="value.preco"
          type="number"
          min="0"
          step="0.01"
          prefix="R$"
          placeholder="0,00"
          :invalid="!!errors.preco"
          @update:model-value="(entrada) => atribuirNumero('preco', entrada)"
        />
      </FormField>
    </div>
  </BaseCard>
</template>
