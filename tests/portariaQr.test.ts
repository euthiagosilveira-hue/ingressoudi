import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  AUTO_RESUME_DELAY_MS,
  SAME_QR_COOLDOWN_MS,
  criarAgendadorUnico,
  deveAutoRetomar,
  deveIgnorarPorCooldown,
  podeIniciarCamera,
  sucessoResultado
} from '../app/utils/portariaQr.ts'
import {
  emitirFeedbackEntrada,
  emitirSomEntrada,
  padraoVibracao,
  vibrarEntrada
} from '../app/utils/portariaFeedback.ts'
import { LeituraLock } from '../app/utils/gate.ts'

// --- leitura / ciclo automatico ----------------------------------------------

test('A. iniciar e idempotente quando a camera esta ativa/solicitando', () => {
  assert.equal(podeIniciarCamera('IDLE'), true)
  assert.equal(podeIniciarCamera('ATIVA'), false)
  assert.equal(podeIniciarCamera('SOLICITANDO'), false)
})

test('B/C. auto-resume e agendado para qualquer resultado de negocio', () => {
  for (const resultado of [
    'LIBERADO',
    'JA_UTILIZADO',
    'INVALIDO',
    'EVENTO_INCORRETO',
    'CANCELADO',
    'NAO_ENCONTRADO'
  ]) {
    assert.equal(
      deveAutoRetomar({ autoHabilitado: true, temResultado: true, erroTecnico: false }),
      true,
      `deveria auto-retomar em ${resultado}`
    )
  }
})

test('D/E. agendador mantem o resultado ate o delay e dispara uma unica vez', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const ag = criarAgendadorUnico()
  let chamadas = 0
  ag.agendar(() => {
    chamadas += 1
  }, AUTO_RESUME_DELAY_MS)
  assert.equal(ag.ativo(), true)
  t.mock.timers.tick(AUTO_RESUME_DELAY_MS - 1)
  assert.equal(chamadas, 0, 'nao deve reabrir antes do delay')
  t.mock.timers.tick(1)
  assert.equal(chamadas, 1)
  assert.equal(ag.ativo(), false)
  t.mock.timers.tick(AUTO_RESUME_DELAY_MS * 3)
  assert.equal(chamadas, 1, 'nao deve disparar de novo')
})

test('F. mesmo token dentro do cooldown e ignorado', () => {
  assert.equal(deveIgnorarPorCooldown('abc', 'abc', 1000, 1000 + SAME_QR_COOLDOWN_MS - 1), true)
  assert.equal(deveIgnorarPorCooldown('abc', 'abc', 1000, 1000 + SAME_QR_COOLDOWN_MS), false)
})

test('G. token diferente nunca e bloqueado pelo cooldown', () => {
  assert.equal(deveIgnorarPorCooldown('abc', 'xyz', 1000, 1100), false)
  assert.equal(deveIgnorarPorCooldown('', 'xyz', 0, 1100), false)
})

test('H/I. pausa cancela o auto-resume; continuar permite reiniciar', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const ag = criarAgendadorUnico()
  let chamadas = 0
  ag.agendar(() => {
    chamadas += 1
  }, AUTO_RESUME_DELAY_MS)
  ag.cancelar()
  assert.equal(ag.ativo(), false)
  t.mock.timers.tick(AUTO_RESUME_DELAY_MS)
  assert.equal(chamadas, 0)
  assert.equal(podeIniciarCamera('IDLE'), true)
})

test('J/K/L. cancelar cobre troca de evento, troca de modo e unmount', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const ag = criarAgendadorUnico()
  let chamadas = 0
  ag.agendar(() => {
    chamadas += 1
  }, AUTO_RESUME_DELAY_MS)
  ag.cancelar() // troca de evento/modo
  ag.agendar(() => {
    chamadas += 1
  }, AUTO_RESUME_DELAY_MS)
  ag.cancelar() // unmount
  t.mock.timers.tick(AUTO_RESUME_DELAY_MS * 2)
  assert.equal(chamadas, 0)
})

test('M. falha tecnica nao entra em loop automatico', () => {
  assert.equal(
    deveAutoRetomar({ autoHabilitado: true, temResultado: false, erroTecnico: true }),
    false
  )
  assert.equal(
    deveAutoRetomar({ autoHabilitado: false, temResultado: true, erroTecnico: false }),
    false
  )
})

test('R. agendamentos concorrentes mantem apenas o ultimo timer', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const ag = criarAgendadorUnico()
  let primeira = 0
  let segunda = 0
  ag.agendar(() => {
    primeira += 1
  }, AUTO_RESUME_DELAY_MS)
  ag.agendar(() => {
    segunda += 1
  }, AUTO_RESUME_DELAY_MS)
  t.mock.timers.tick(AUTO_RESUME_DELAY_MS)
  assert.equal(primeira, 0)
  assert.equal(segunda, 1)
})

test('Q. LeituraLock continua impedindo requests simultaneos', () => {
  const lock = new LeituraLock()
  let rpc = 0
  const tentar = () => {
    if (!lock.podeProcessar()) return
    lock.bloquear()
    rpc += 1
  }
  tentar()
  tentar()
  tentar()
  assert.equal(rpc, 1)
  lock.liberar()
  tentar()
  assert.equal(rpc, 2)
})

// --- feedback fisico/sonoro ---------------------------------------------------

function audioFake() {
  const freqs: number[] = []
  return {
    currentTime: 0,
    state: 'running',
    destination: {},
    freqs,
    createOscillator() {
      return {
        type: 'sine',
        frequency: { setValueAtTime: (v: number) => freqs.push(v) },
        connect() {},
        start() {},
        stop() {}
      }
    },
    createGain() {
      return {
        gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} },
        connect() {}
      }
    }
  }
}

test('N. vibra quando suportado (sucesso x bloqueio)', () => {
  const chamadas: Array<number | number[]> = []
  const vibrate = (p: number | number[]) => {
    chamadas.push(p)
    return true
  }
  vibrarEntrada('LIBERADO', vibrate)
  vibrarEntrada('JA_UTILIZADO', vibrate)
  assert.deepEqual(chamadas[0], 120)
  assert.deepEqual(chamadas[1], [120, 70, 120])
  assert.deepEqual(padraoVibracao('LIBERADO'), 120)
  assert.deepEqual(padraoVibracao('INVALIDO'), [120, 70, 120])
})

test('O. ausencia de navigator.vibrate nao quebra', () => {
  assert.doesNotThrow(() => vibrarEntrada('LIBERADO', null))
  assert.doesNotThrow(() => vibrarEntrada('LIBERADO', undefined))
})

test('P. audio nao suportado/bloqueado nao quebra', () => {
  assert.doesNotThrow(() => emitirSomEntrada('LIBERADO', { ctor: null }))
  assert.doesNotThrow(() =>
    emitirSomEntrada('LIBERADO', {
      ctor: () => {
        throw new Error('blocked')
      }
    })
  )
  assert.doesNotThrow(() => emitirFeedbackEntrada('LIBERADO', { vibrate: null, ctor: null }))
})

test('som de sucesso difere do som de bloqueio', () => {
  const ctx = audioFake()
  emitirSomEntrada('LIBERADO', { ctx })
  const sucesso = [...ctx.freqs]
  ctx.freqs.length = 0
  emitirSomEntrada('INVALIDO', { ctx })
  const bloqueio = [...ctx.freqs]
  assert.ok(sucesso.length >= 1)
  assert.ok(bloqueio.length >= 2)
  assert.notDeepEqual(sucesso, bloqueio)
  assert.equal(sucessoResultado('LIBERADO'), true)
  assert.equal(sucessoResultado('INVALIDO'), false)
})
