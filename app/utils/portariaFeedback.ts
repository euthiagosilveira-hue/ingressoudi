import { sucessoResultado } from './portariaQr.ts'

/**
 * Feedback fisico/sonoro da portaria. Tudo com degradacao graciosa:
 * se o navegador nao suportar, ignora silenciosamente. Nunca e o unico
 * feedback (o visual permanece).
 */

export type VibrateFn = ((pattern: number | number[]) => boolean) | null | undefined

export interface AudioContextLike {
  currentTime: number
  state?: string
  destination: unknown
  createOscillator: () => {
    type: string
    frequency: { setValueAtTime: (value: number, start: number) => void }
    connect: (dest: unknown) => void
    start: (when?: number) => void
    stop: (when?: number) => void
  }
  createGain: () => {
    gain: {
      setValueAtTime: (value: number, start: number) => void
      exponentialRampToValueAtTime: (value: number, start: number) => void
    }
    connect: (dest: unknown) => void
  }
  resume?: () => Promise<void>
}

export type AudioContextCtor = (new () => AudioContextLike) | null | undefined

export interface FeedbackDeps {
  vibrate?: VibrateFn
  ctx?: AudioContextLike | null
  ctor?: AudioContextCtor
}

export function padraoVibracao(resultado: string | null | undefined): number | number[] {
  return sucessoResultado(resultado) ? 120 : [120, 70, 120]
}

function vibrateGlobal(): VibrateFn {
  const nav = (globalThis as { navigator?: { vibrate?: unknown } }).navigator
  const fn = nav?.vibrate
  return typeof fn === 'function' ? (fn.bind(nav) as VibrateFn) : null
}

/** Vibra conforme o resultado; ignora se nao suportado. */
export function vibrarEntrada(
  resultado: string | null | undefined,
  vibrate?: VibrateFn
): void {
  const fn = vibrate === undefined ? vibrateGlobal() : vibrate
  if (typeof fn !== 'function') return
  try {
    fn(padraoVibracao(resultado))
  } catch {
    /* ignora */
  }
}

let ctxCache: AudioContextLike | null = null

function audioCtorGlobal(): AudioContextCtor {
  const g = globalThis as {
    AudioContext?: new () => AudioContextLike
    webkitAudioContext?: new () => AudioContextLike
  }
  return g.AudioContext ?? g.webkitAudioContext ?? null
}

function obterContexto(deps?: FeedbackDeps): AudioContextLike | null {
  if (deps && 'ctx' in deps) return deps.ctx ?? null
  if (ctxCache) return ctxCache
  const Ctor = deps && 'ctor' in deps ? deps.ctor : audioCtorGlobal()
  if (!Ctor) return null
  try {
    ctxCache = new Ctor()
    return ctxCache
  } catch {
    return null
  }
}

/** Cria/resume o contexto de audio a partir de um gesto do usuario. */
export function desbloquearAudio(): void {
  const ctx = obterContexto()
  if (!ctx) return
  if (ctx.state === 'suspended') void ctx.resume?.()
}

interface Tom {
  tipo: OscillatorType
  freq: number
  dur: number
  at: number
}

/** Agenda os tons do resultado em um AudioContext-like. */
export function tocarSom(ctx: AudioContextLike, resultado: string | null | undefined): void {
  const sucesso = sucessoResultado(resultado)
  const tons: Tom[] = sucesso
    ? [{ tipo: 'sine', freq: 988, dur: 0.12, at: 0 }]
    : [
        { tipo: 'square', freq: 220, dur: 0.16, at: 0 },
        { tipo: 'square', freq: 180, dur: 0.18, at: 0.18 }
      ]

  const inicio = ctx.currentTime
  for (const tom of tons) {
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    const t0 = inicio + tom.at
    const t1 = t0 + tom.dur
    osc.type = tom.tipo
    osc.frequency.setValueAtTime(tom.freq, t0)
    gain.gain.setValueAtTime(0.0001, t0)
    gain.gain.exponentialRampToValueAtTime(0.2, t0 + 0.01)
    gain.gain.exponentialRampToValueAtTime(0.0001, t1)
    osc.connect(gain)
    gain.connect(ctx.destination)
    osc.start(t0)
    osc.stop(t1 + 0.02)
  }
}

/** Emite o som do resultado; ignora se audio bloqueado/nao suportado. */
export function emitirSomEntrada(
  resultado: string | null | undefined,
  deps?: FeedbackDeps
): void {
  const ctx = obterContexto(deps)
  if (!ctx) return
  if (ctx.state === 'suspended') void ctx.resume?.()
  try {
    tocarSom(ctx, resultado)
  } catch {
    /* ignora */
  }
}

/** Ponto unico de feedback fisico + sonoro (facilita futuras preferencias). */
export function emitirFeedbackEntrada(
  resultado: string | null | undefined,
  deps?: FeedbackDeps
): void {
  vibrarEntrada(resultado, deps?.vibrate)
  emitirSomEntrada(resultado, deps)
}
