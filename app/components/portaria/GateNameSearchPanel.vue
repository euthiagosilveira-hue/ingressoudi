<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import {
  CheckCircleIcon,
  ExclamationTriangleIcon,
  MagnifyingGlassIcon,
  TicketIcon,
  XCircleIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import ConfirmDialog from '~/components/ConfirmDialog.vue'
import { useGateNameSearch } from '~/composables/useGateNameSearch'
import type { GateScanErroCode, IngressoBuscaNome } from '~/types/gate'
import { formatDataHoraCompleta } from '~/utils/format'
import {
  descricaoResultadoEntrada,
  chaveBuscaPortaria,
  ingressoRegistravel,
  rotuloResultadoEntrada,
  uuidValido
} from '~/utils/gate'
import {
  descricaoConfirmacao,
  itemExigeConfirmacao,
  mascararTelefone,
  nomesAmbiguos,
  precisaHintNome,
  rotuloOrigem
} from '~/utils/portariaBusca'
import { ehErroTecnico, mensagemErroTecnico } from '~/utils/portariaErro'

const props = defineProps<{
  eventoId: string
}>()

const {
  nome,
  buscando,
  registrando,
  resultados,
  resultado,
  erro,
  contextoErro,
  itemParaRetry,
  jaBuscou,
  nomeValido,
  podeBuscar,
  buscar,
  registrar,
  tentarBuscarNovamente,
  tentarRegistrarNovamente,
  reset
} = useGateNameSearch(() => props.eventoId)

const temEvento = computed(() => uuidValido(props.eventoId))
const inputNome = ref<HTMLInputElement | null>(null)
const itemPendente = ref<IngressoBuscaNome | null>(null)

const ROTULOS_STATUS: Record<string, string> = {
  VALIDO: 'Válido',
  UTILIZADO: 'Utilizado',
  RESERVADO: 'Reservado',
  CANCELADO: 'Cancelado',
  EXPIRADO: 'Expirado'
}

function rotuloStatus(status: string): string {
  return ROTULOS_STATUS[status] ?? status
}

function mensagemErro(codigo: GateScanErroCode): string {
  if (ehErroTecnico(codigo)) return mensagemErroTecnico(codigo)
  if (codigo === 'SEM_EVENTO') return 'Selecione um evento para buscar ingressos.'
  return 'Não foi possível concluir a operação.'
}

const rotulo = computed(() =>
  resultado.value ? rotuloResultadoEntrada(resultado.value.resultado) : null
)

const descricaoResultado = computed(() =>
  resultado.value
    ? descricaoResultadoEntrada(resultado.value.resultado, resultado.value.mensagem)
    : ''
)

const erroTecnicoRegistro = computed(
  () => contextoErro.value === 'REGISTRO' && Boolean(erro.value)
)
const erroBusca = computed(() => contextoErro.value === 'BUSCA' && Boolean(erro.value))
const podeRetentarRegistro = computed(() => Boolean(itemParaRetry.value))

const nomesAmbiguosSet = computed(() => nomesAmbiguos(resultados.value))

function ehAmbiguo(item: IngressoBuscaNome): boolean {
  return itemExigeConfirmacao(item, resultados.value)
}

const descricaoPendente = computed(() =>
  itemPendente.value ? descricaoConfirmacao(itemPendente.value) : ''
)

const statusPendente = computed(() =>
  itemPendente.value ? rotuloStatus(itemPendente.value.status) : ''
)

/** Registro direto se nao-ambiguo; senao abre confirmacao. */
function solicitarRegistro(item: IngressoBuscaNome) {
  if (!ingressoRegistravel(item.status)) return
  if (ehAmbiguo(item)) {
    itemPendente.value = item
    return
  }
  void registrar(item)
}

function confirmarRegistro() {
  const item = itemPendente.value
  itemPendente.value = null
  if (item) void registrar(item)
}

function cancelarRegistro() {
  itemPendente.value = null
}

function executarBusca() {
  itemPendente.value = null
  void buscar()
}

async function novaBusca() {
  itemPendente.value = null
  reset()
  await nextTick()
  inputNome.value?.focus()
}
</script>

<template>
  <BaseCard class="space-y-4">
    <!-- Sem evento -->
    <div
      v-if="!temEvento"
      class="rounded-2xl border border-dashed border-zinc-700 bg-zinc-950 p-6 text-center"
    >
      <MagnifyingGlassIcon class="mx-auto h-12 w-12 text-zinc-700" />
      <p class="mt-3 text-sm text-zinc-400">Selecione um evento para buscar ingressos.</p>
    </div>

    <!-- Resultado de registro / erro tecnico de registro -->
    <div
      v-else-if="resultado || erroTecnicoRegistro"
      role="status"
      aria-live="assertive"
      class="space-y-4 rounded-2xl border-2 bg-zinc-950 p-5"
      :class="rotulo?.sucesso ? 'border-green-500/60' : 'border-red-500/50'"
    >
      <div class="flex items-center gap-4">
        <span
          class="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900"
        >
          <CheckCircleIcon v-if="rotulo?.sucesso" class="h-7 w-7 text-green-300" />
          <ExclamationTriangleIcon
            v-else-if="erroTecnicoRegistro"
            class="h-7 w-7 text-amber-400"
          />
          <XCircleIcon v-else class="h-7 w-7 text-red-300" />
        </span>
        <div class="min-w-0">
          <p
            class="text-lg font-bold uppercase tracking-wide"
            :class="
              rotulo?.sucesso
                ? 'text-green-300'
                : erroTecnicoRegistro
                  ? 'text-amber-300'
                  : 'text-red-300'
            "
          >
            {{
              rotulo
                ? rotulo.titulo
                : erroTecnicoRegistro
                  ? 'Falha na conexão'
                  : 'Não foi possível registrar'
            }}
          </p>
          <p class="text-sm text-zinc-400">
            {{
              erro && !resultado ? mensagemErro(erro as GateScanErroCode) : descricaoResultado
            }}
          </p>
        </div>
      </div>

      <dl
        v-if="resultado && (resultado.participanteNome || resultado.codigo)"
        class="space-y-1 rounded-xl border border-zinc-800 bg-zinc-900 p-3 text-sm"
      >
        <div v-if="resultado.participanteNome" class="flex justify-between gap-3">
          <dt class="text-zinc-500">Participante</dt>
          <dd class="min-w-0 break-words text-right font-semibold text-zinc-100">
            {{ resultado.participanteNome }}
          </dd>
        </div>
        <div v-if="resultado.codigo" class="flex justify-between gap-3">
          <dt class="text-zinc-500">Ingresso</dt>
          <dd class="min-w-0 break-all text-right text-zinc-200">{{ resultado.codigo }}</dd>
        </div>
        <div v-if="resultado.entradaEm" class="flex justify-between gap-3">
          <dt class="text-zinc-500">Entrada</dt>
          <dd class="text-zinc-200">{{ formatDataHoraCompleta(resultado.entradaEm) }}</dd>
        </div>
      </dl>

      <div v-if="erroTecnicoRegistro" class="space-y-2">
        <AppButton
          v-if="podeRetentarRegistro"
          variant="primary"
          size="lg"
          block
          :disabled="registrando"
          @click="tentarRegistrarNovamente"
        >
          {{ registrando ? 'Tentando...' : 'Tentar novamente' }}
        </AppButton>
        <AppButton variant="ghost" size="lg" block :disabled="registrando" @click="novaBusca">
          Nova busca
        </AppButton>
      </div>
      <AppButton v-else variant="primary" size="lg" block @click="novaBusca">Nova busca</AppButton>
    </div>

    <!-- Busca -->
    <template v-else>
      <form class="space-y-3" @submit.prevent="executarBusca">
        <div class="space-y-1.5">
          <label
            for="gate-nome"
            class="block text-xs font-semibold uppercase tracking-wide text-zinc-400"
          >
            Nome do participante
          </label>
          <input
            id="gate-nome"
            ref="inputNome"
            v-model="nome"
            type="text"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="words"
            spellcheck="false"
            enterkeyhint="search"
            class="w-full rounded-xl border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm text-zinc-100 placeholder:text-zinc-600 focus:border-amber-400/60 focus:outline-none focus:ring-2 focus:ring-amber-400/30"
            placeholder="Digite o nome completo"
          />
          <p v-if="precisaHintNome(nome)" class="text-xs text-zinc-500">
            Informe o nome completo (mínimo 2 caracteres).
          </p>
        </div>

        <AppButton
          type="submit"
          variant="primary"
          size="lg"
          block
          :disabled="!podeBuscar || buscando"
        >
          {{ buscando ? 'Buscando...' : 'Buscar' }}
        </AppButton>
      </form>

      <p v-if="erro === 'SEM_EVENTO'" class="text-sm text-zinc-400">
        Selecione um evento para buscar ingressos.
      </p>

      <div v-else-if="erroBusca" class="space-y-2" role="alert">
        <p class="text-sm text-red-300">{{ mensagemErro(erro as GateScanErroCode) }}</p>
        <AppButton variant="outline" block :disabled="buscando" @click="tentarBuscarNovamente">
          Tentar novamente
        </AppButton>
      </div>

      <div
        v-if="jaBuscou && !buscando && resultados.length === 0 && !erro"
        class="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4 text-center text-sm text-zinc-400"
      >
        Nenhum ingresso encontrado com esse nome neste evento.
      </div>

      <ul v-if="resultados.length > 0" class="space-y-3" aria-live="polite">
        <li v-for="item in resultados" :key="chaveBuscaPortaria(item)">
          <div
            class="flex items-center justify-between gap-3 rounded-2xl border border-zinc-800 bg-zinc-950/60 p-4"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <p class="truncate text-sm font-semibold text-white">
                  {{ item.participanteNome }}
                </p>
                <span
                  v-if="item.origem === 'VIP'"
                  class="inline-flex items-center rounded-full border border-amber-400/50 bg-amber-400/10 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-amber-300"
                >
                  VIP
                </span>
              </div>

              <p v-if="item.origem === 'VIP'" class="text-xs text-zinc-500">Lista VIP</p>
              <p v-else class="text-xs text-zinc-500">Ingresso {{ item.codigo }}</p>

              <p v-if="mascararTelefone(item.telefone)" class="text-xs text-zinc-500">
                Tel. {{ mascararTelefone(item.telefone) }}
              </p>

              <div class="mt-1 flex flex-wrap items-center gap-2">
                <span
                  class="inline-flex items-center rounded-full border border-zinc-700 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-zinc-300"
                >
                  {{ rotuloStatus(item.status) }}
                </span>
                <span
                  v-if="ehAmbiguo(item)"
                  class="inline-flex items-center rounded-full border border-amber-400/40 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-300"
                >
                  Homônimo
                </span>
              </div>
            </div>

            <AppButton
              v-if="ingressoRegistravel(item.status)"
              variant="primary"
              size="lg"
              class="min-h-[44px] shrink-0"
              :disabled="registrando"
              @click="solicitarRegistro(item)"
            >
              <TicketIcon class="h-4 w-4" />
              Registrar
            </AppButton>
            <div v-else class="shrink-0 text-right">
              <span
                class="inline-flex items-center rounded-full border border-zinc-700 px-3 py-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-400"
              >
                {{ item.status === 'UTILIZADO' ? 'Já utilizado' : rotuloStatus(item.status) }}
              </span>
              <p
                v-if="item.entradaEm ?? item.utilizadoEm"
                class="mt-1 text-[11px] text-zinc-500"
              >
                {{ formatDataHoraCompleta(item.entradaEm ?? item.utilizadoEm ?? '') }}
              </p>
            </div>
          </div>
        </li>
      </ul>
    </template>

    <ConfirmDialog
      :open="itemPendente !== null"
      title="Confirmar entrada"
      :description="`${descricaoPendente} • ${statusPendente}`"
      confirm-label="Confirmar entrada"
      :loading="registrando"
      @confirm="confirmarRegistro"
      @cancel="cancelarRegistro"
    />
  </BaseCard>
</template>
