import { computed, nextTick, onUnmounted, ref, watch } from 'vue'

import { useGateSession } from '~/composables/useGateSession'
import { GateError, registrarEntradaQr } from '~/services/gate/entradas'
import type {
  GateCameraStatus,
  GateScanErroCode,
  RegistrarEntradaQrResult
} from '~/types/gate'
import { LeituraLock, qrTokenPlausivel, uuidValido } from '~/utils/gate'
import { desbloquearAudio, emitirFeedbackEntrada } from '~/utils/portariaFeedback'
import {
  AUTO_RESUME_DELAY_MS,
  criarAgendadorUnico,
  deveAutoRetomar,
  deveIgnorarPorCooldown,
  podeIniciarCamera
} from '~/utils/portariaQr'

const INTERVALO_LEITURA_MS = 120
const LARGURA_MAX_PX = 480

type Decodificador = typeof import('jsqr')['default']

/**
 * Scanner de portaria: camera (getUserMedia) + decode local (jsQR) +
 * chamada unica a RPC registrar_entrada_qr por leitura.
 *
 * Fluxo automatico:
 *   QR -> lock -> RPC -> resultado (som/vibracao) -> aguarda AUTO_RESUME_DELAY_MS
 *   -> limpa resultado -> reabre a camera. O operador pode pausar/continuar ou
 *   avancar na hora. Erro TECNICO (transporte) NAO entra em loop automatico:
 *   guarda o token da tentativa para "Tentar novamente" ou "Ler outro codigo".
 */
export function useGateScanner(eventoId: () => string) {
  const video = ref<HTMLVideoElement | null>(null)
  const cameraStatus = ref<GateCameraStatus>('IDLE')
  const lendo = ref(false)
  const processando = ref(false)
  const resultado = ref<RegistrarEntradaQrResult | null>(null)
  const erro = ref<GateScanErroCode | null>(null)
  const pausado = ref(false)
  // Token da ultima tentativa que falhou tecnicamente (para retry explicito).
  const tokenPendente = ref('')

  const lock = new LeituraLock()
  const agendador = criarAgendadorUnico()
  const { registrar } = useGateSession()
  let stream: MediaStream | null = null
  let raf: number | null = null
  let canvas: HTMLCanvasElement | null = null
  let ctx: CanvasRenderingContext2D | null = null
  let decodificador: Decodificador | null = null
  let ultimaLeitura = 0
  let desmontado = false
  // Cooldown do MESMO token: guarda o ultimo token processado e o instante.
  let tokenProcessado = ''
  let tokenProcessadoEm = 0

  function pararLoop() {
    if (raf !== null) {
      cancelAnimationFrame(raf)
      raf = null
    }
  }

  function parar() {
    pararLoop()
    if (stream) {
      for (const track of stream.getTracks()) track.stop()
      stream = null
    }
    if (video.value) video.value.srcObject = null
    cameraStatus.value = 'IDLE'
  }

  function limparCooldown() {
    tokenProcessado = ''
    tokenProcessadoEm = 0
  }

  function limparResultado() {
    resultado.value = null
    erro.value = null
    lendo.value = false
    tokenPendente.value = ''
    lock.liberar()
  }

  async function carregarDecodificador(): Promise<Decodificador> {
    if (!decodificador) {
      const mod = await import('jsqr')
      decodificador = mod.default
    }
    return decodificador
  }

  async function abrirStream(): Promise<MediaStream> {
    const restricoes: MediaStreamConstraints = {
      video: { facingMode: { ideal: 'environment' } },
      audio: false
    }
    try {
      return await navigator.mediaDevices.getUserMedia(restricoes)
    } catch (e) {
      const nome = (e as DOMException)?.name
      // Dispositivo pode nao ter camera traseira: cai para qualquer camera.
      if (nome === 'OverconstrainedError' || nome === 'NotFoundError') {
        return await navigator.mediaDevices.getUserMedia({ video: true, audio: false })
      }
      throw e
    }
  }

  async function iniciar() {
    if (!import.meta.client || desmontado) return
    if (!podeIniciarCamera(cameraStatus.value)) return
    if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
      cameraStatus.value = 'SEM_SUPORTE'
      return
    }

    // Inicializa o audio no gesto do usuario (politica de autoplay).
    desbloquearAudio()

    cameraStatus.value = 'SOLICITANDO'
    erro.value = null

    try {
      stream = await abrirStream()
      cameraStatus.value = 'ATIVA'
      await nextTick()

      const el = video.value
      if (!el) {
        cameraStatus.value = 'ERRO'
        return
      }
      el.srcObject = stream
      el.setAttribute('playsinline', 'true')
      el.muted = true
      await el.play().catch(() => {})
      await carregarDecodificador()
      loop()
    } catch (e) {
      parar()
      const nome = (e as DOMException)?.name
      if (nome === 'NotAllowedError' || nome === 'SecurityError') {
        cameraStatus.value = 'NEGADA'
      } else if (nome === 'NotFoundError' || nome === 'OverconstrainedError') {
        cameraStatus.value = 'INDISPONIVEL'
      } else {
        cameraStatus.value = 'ERRO'
      }
    }
  }

  function loop() {
    raf = requestAnimationFrame(loop)

    const el = video.value
    if (!el || el.readyState < 2) return
    if (!lock.podeProcessar() || processando.value) return

    const agora = performance.now()
    if (agora - ultimaLeitura < INTERVALO_LEITURA_MS) return
    ultimaLeitura = agora

    if (!canvas) {
      canvas = document.createElement('canvas')
      ctx = canvas.getContext('2d', { willReadFrequently: true })
    }
    if (!ctx || !decodificador) return

    const vw = el.videoWidth
    const vh = el.videoHeight
    if (!vw || !vh) return

    const escala = Math.min(1, LARGURA_MAX_PX / Math.max(vw, vh))
    const largura = Math.max(1, Math.round(vw * escala))
    const altura = Math.max(1, Math.round(vh * escala))
    canvas.width = largura
    canvas.height = altura

    ctx.drawImage(el, 0, 0, largura, altura)
    const imagem = ctx.getImageData(0, 0, largura, altura)
    const codigo = decodificador(imagem.data, largura, altura, { inversionAttempts: 'dontInvert' })

    if (codigo?.data) {
      void aoDetectar(codigo.data)
    }
  }

  function agendarAutoResume() {
    if (
      !deveAutoRetomar({
        autoHabilitado: !pausado.value,
        temResultado: Boolean(resultado.value),
        erroTecnico: Boolean(erro.value)
      })
    ) {
      return
    }
    agendador.agendar(() => {
      if (desmontado || pausado.value) return
      // Mantem o cooldown: o mesmo QR continua bloqueado por alguns segundos.
      limparResultado()
      void iniciar()
    }, AUTO_RESUME_DELAY_MS)
  }

  /** Executa a RPC para um token. Usado pelo scanner e pelo retry explicito. */
  async function executarRegistro(token: string) {
    if (processando.value || desmontado) return

    const evento = eventoId()
    if (!evento || !uuidValido(evento)) {
      erro.value = 'SEM_EVENTO'
      parar()
      return
    }

    processando.value = true
    try {
      resultado.value = await registrarEntradaQr({ eventoId: evento, qrToken: token })
      erro.value = null
      tokenPendente.value = ''
      // Contabiliza a sessao apenas se LIBERADO (regra no reducer).
      registrar(resultado.value.resultado, {
        nome: resultado.value.participanteNome ?? 'Ingresso liberado',
        tipo: 'INGRESSO',
        codigo: resultado.value.codigo
      })
      // Feedback apenas para resultado de negocio.
      emitirFeedbackEntrada(resultado.value?.resultado ?? null)
    } catch (e) {
      resultado.value = null
      erro.value = e instanceof GateError ? e.code : 'DESCONHECIDO'
      // Guarda o token para permitir "Tentar novamente".
      tokenPendente.value = token
    } finally {
      processando.value = false
      // Desliga a camera ao exibir o resultado (economia/privacidade).
      parar()
      agendarAutoResume()
    }
  }

  async function aoDetectar(tokenBruto: string) {
    if (!lock.podeProcessar() || processando.value) return

    const token = tokenBruto.trim()
    // Formato basico apenas; nenhuma regra de negocio aqui.
    if (!qrTokenPlausivel(token)) return

    // Protecao de UX: ignora o MESMO token dentro da janela de cooldown.
    if (deveIgnorarPorCooldown(tokenProcessado, token, tokenProcessadoEm, performance.now())) {
      return
    }

    lock.bloquear()
    lendo.value = true
    tokenProcessado = token
    tokenProcessadoEm = performance.now()

    await executarRegistro(token)
  }

  /** Avanca imediatamente (pula a espera do auto-resume). */
  function lerProximoAgora() {
    agendador.cancelar()
    limparCooldown()
    limparResultado()
    void iniciar()
  }

  /** Pausa o fluxo automatico: cancela timer e desliga a camera. */
  function pausar() {
    agendador.cancelar()
    pausado.value = true
    limparCooldown()
    limparResultado()
    parar()
  }

  /** Retoma o fluxo automatico. */
  function continuar() {
    pausado.value = false
    limparCooldown()
    limparResultado()
    void iniciar()
  }

  /**
   * Retry EXPLICITO do token que falhou tecnicamente. Ignora o cooldown
   * (acao do operador), respeita processando (uma RPC por clique).
   */
  function tentarNovamente() {
    const token = tokenPendente.value
    if (!token || processando.value) return
    agendador.cancelar()
    limparCooldown()
    void executarRegistro(token)
  }

  /** Descarta a tentativa e volta ao scanner (mesmo que "Ler proximo agora"). */
  function lerOutroCodigo() {
    lerProximoAgora()
  }

  /** Reset mantendo o cooldown (usado por fluxos externos/legado). */
  function reiniciar() {
    limparResultado()
  }

  // Troca de evento: cancela o ciclo anterior por completo.
  watch(eventoId, () => {
    agendador.cancelar()
    limparCooldown()
    limparResultado()
    parar()
  })

  onUnmounted(() => {
    desmontado = true
    agendador.cancelar()
    parar()
  })

  return {
    video,
    cameraStatus,
    lendo,
    processando,
    resultado,
    erro,
    pausado,
    retentativaPendente: computed(() => Boolean(tokenPendente.value)),
    iniciar,
    parar,
    reiniciar,
    lerProximoAgora,
    tentarNovamente,
    lerOutroCodigo,
    pausar,
    continuar
  }
}
