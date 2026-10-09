<script setup lang="ts">
import { computed } from 'vue'
import {
  CameraIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon
} from '@heroicons/vue/24/outline'

import AppButton from '~/components/AppButton.vue'
import BaseCard from '~/components/BaseCard.vue'
import { useGateScanner } from '~/composables/useGateScanner'
import type { GateScanErroCode } from '~/types/gate'
import { formatDataHoraCompleta } from '~/utils/format'
import {
  descricaoResultadoEntrada,
  rotuloResultadoEntrada,
  uuidValido
} from '~/utils/gate'
import { ehErroTecnico, mensagemErroTecnico } from '~/utils/portariaErro'

const props = defineProps<{
  eventoId: string
}>()

const {
  video,
  cameraStatus,
  processando,
  resultado,
  erro,
  pausado,
  retentativaPendente,
  iniciar,
  lerProximoAgora,
  tentarNovamente,
  lerOutroCodigo,
  pausar,
  continuar
} = useGateScanner(() => props.eventoId)

const cameraAtiva = computed(() => cameraStatus.value === 'ATIVA')
const mostraResultado = computed(() => Boolean(resultado.value) || Boolean(erro.value))
const temEvento = computed(() => uuidValido(props.eventoId))
const erroTecnico = computed(() => Boolean(erro.value) && !resultado.value)

const MENSAGENS_CAMERA: Record<string, string> = {
  SOLICITANDO: 'Solicitando acesso à câmera...',
  NEGADA: 'Permissão de câmera negada. Autorize o acesso nas configurações do navegador.',
  INDISPONIVEL: 'Câmera indisponível neste dispositivo. Use a busca por nome.',
  SEM_SUPORTE: 'Este navegador não suporta leitura por câmera. Use a busca por nome.',
  ERRO: 'Não foi possível iniciar a câmera. Tente novamente.'
}

function mensagemErro(codigo: GateScanErroCode): string {
  if (ehErroTecnico(codigo)) return mensagemErroTecnico(codigo)
  if (codigo === 'SEM_EVENTO') return 'Selecione um evento válido para registrar entradas.'
  if (codigo === 'QR_INVALIDO') return 'QR Code inválido. Posicione novamente.'
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

const cameraFallback = computed(() =>
  ['NEGADA', 'INDISPONIVEL', 'SEM_SUPORTE', 'ERRO'].includes(cameraStatus.value)
)
</script>

<template>
  <BaseCard class="space-y-4">
    <!-- Resultado / erro -->
    <div
      v-if="mostraResultado"
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
          <XCircleIcon v-else-if="rotulo" class="h-7 w-7 text-red-300" />
          <ExclamationTriangleIcon v-else class="h-7 w-7 text-amber-400" />
        </span>
        <div class="min-w-0">
          <p
            class="text-lg font-bold uppercase tracking-wide"
            :class="rotulo?.sucesso ? 'text-green-300' : 'text-red-300'"
          >
            {{ rotulo ? rotulo.titulo : erroTecnico ? 'Falha na conexão' : 'Não foi possível validar' }}
          </p>
          <p class="text-sm text-zinc-400">
            {{ erro && !resultado ? mensagemErro(erro as GateScanErroCode) : descricaoResultado }}
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

      <!-- Erro tecnico: retry do MESMO token (sem reabrir a camera) ou novo codigo -->
      <div v-if="erroTecnico" class="space-y-2">
        <AppButton
          v-if="retentativaPendente"
          variant="primary"
          size="lg"
          block
          :disabled="processando"
          @click="tentarNovamente"
        >
          {{ processando ? 'Tentando...' : 'Tentar novamente' }}
        </AppButton>
        <AppButton variant="ghost" size="lg" block :disabled="processando" @click="lerOutroCodigo">
          Ler outro código
        </AppButton>
      </div>

      <!-- Resultado de negocio -->
      <div v-else class="space-y-2">
        <AppButton variant="primary" size="lg" block @click="lerProximoAgora">
          Ler próximo agora
        </AppButton>
        <AppButton v-if="!pausado" variant="ghost" size="lg" block @click="pausar">
          Pausar leitura
        </AppButton>
      </div>
    </div>

    <!-- Sem evento selecionado: scanner bloqueado -->
    <div
      v-else-if="!temEvento"
      class="rounded-2xl border border-dashed border-zinc-700 bg-zinc-950 p-6 text-center"
    >
      <CameraIcon class="mx-auto h-12 w-12 text-zinc-700" />
      <p class="mt-3 text-sm text-zinc-400">Selecione um evento para iniciar a leitura.</p>
    </div>

    <!-- Camera -->
    <template v-else>
      <div
        class="relative mx-auto aspect-square w-full max-w-sm overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950"
      >
        <video
          ref="video"
          class="h-full w-full object-cover"
          playsinline
          muted
          :class="cameraAtiva ? 'opacity-100' : 'opacity-0'"
        ></video>

        <div
          v-if="!cameraAtiva"
          class="absolute inset-0 flex flex-col items-center justify-center gap-3 px-6 text-center"
        >
          <CameraIcon class="h-14 w-14 text-zinc-700" />
          <p class="text-sm text-zinc-400">
            {{ MENSAGENS_CAMERA[cameraStatus] ?? 'Ative a câmera para ler o QR Code.' }}
          </p>
        </div>

        <template v-if="cameraAtiva">
          <span class="absolute left-4 top-4 h-8 w-8 rounded-tl-lg border-l-2 border-t-2 border-amber-400" />
          <span class="absolute right-4 top-4 h-8 w-8 rounded-tr-lg border-r-2 border-t-2 border-amber-400" />
          <span class="absolute bottom-4 left-4 h-8 w-8 rounded-bl-lg border-b-2 border-l-2 border-amber-400" />
          <span class="absolute bottom-4 right-4 h-8 w-8 rounded-br-lg border-b-2 border-r-2 border-amber-400" />
          <span
            v-if="processando"
            class="absolute inset-x-0 bottom-0 bg-zinc-950/80 py-2 text-center text-xs font-semibold uppercase tracking-wide text-amber-300"
          >
            Registrando entrada...
          </span>
          <span
            v-else
            class="absolute inset-x-0 bottom-0 bg-zinc-950/80 py-2 text-center text-xs font-medium uppercase tracking-wide text-zinc-300"
          >
            Lendo...
          </span>
        </template>
      </div>

      <p class="text-center text-xs text-zinc-500">
        Posicione o QR Code do ingresso dentro da área.
      </p>

      <AppButton v-if="pausado" variant="primary" size="lg" block @click="continuar">
        Continuar leitura
      </AppButton>
      <AppButton v-else-if="!cameraAtiva" variant="primary" size="lg" block @click="iniciar">
        Ativar câmera
      </AppButton>
      <AppButton v-else variant="outline" size="lg" block @click="pausar">
        Pausar leitura
      </AppButton>

      <p v-if="cameraFallback" class="text-center text-xs text-zinc-500">
        Alternativa: use a aba <span class="font-semibold text-zinc-300">Buscar por nome</span>.
      </p>
    </template>
  </BaseCard>
</template>
