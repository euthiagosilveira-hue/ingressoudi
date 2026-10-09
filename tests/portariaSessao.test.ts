import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  SESSAO_VAZIA,
  deveContarEntrada,
  formatarHorarioSessao,
  montarUltimaEntrada,
  registrarNaSessao,
  resetarSessao
} from '../app/utils/portariaSessao.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const gateApp = ler('../app/components/portaria/GateApp.vue')
const gateHeader = ler('../app/components/portaria/GateHeader.vue')
const scanner = ler('../app/composables/useGateScanner.ts')
const busca = ler('../app/composables/useGateNameSearch.ts')

test('A. estado inicial total 0 e ultima null', () => {
  assert.equal(SESSAO_VAZIA.total, 0)
  assert.equal(SESSAO_VAZIA.ultima, null)
  assert.deepEqual(resetarSessao(), { total: 0, ultima: null })
})

test('B/C. LIBERADO incrementa 1 e depois 2', () => {
  let s = SESSAO_VAZIA
  s = registrarNaSessao(s, { resultado: 'LIBERADO', nome: 'A', tipo: 'INGRESSO', horario: '21:00' })
  assert.equal(s.total, 1)
  s = registrarNaSessao(s, { resultado: 'LIBERADO', nome: 'B', tipo: 'INGRESSO', horario: '21:01' })
  assert.equal(s.total, 2)
})

test('D/E/F. bloqueio, invalido e erro tecnico nao incrementam (mesma referencia)', () => {
  const base = {
    total: 3,
    ultima: { nome: 'X', tipo: 'INGRESSO' as const, codigo: null, horario: '20:00' }
  }
  const resultados = [
    'JA_UTILIZADO',
    'INVALIDO',
    'EVENTO_INCORRETO',
    'CANCELADO',
    'NAO_ENCONTRADO',
    null,
    undefined,
    'ERRO_TEMPORARIO',
    ''
  ]
  for (const resultado of resultados) {
    const r = registrarNaSessao(base, {
      resultado,
      nome: 'Y',
      tipo: 'INGRESSO',
      horario: '21:00'
    })
    assert.equal(r, base, `nao deveria contar em ${String(resultado)}`)
    assert.equal(r.total, 3)
  }
  assert.equal(deveContarEntrada('LIBERADO'), true)
  assert.equal(deveContarEntrada('JA_UTILIZADO'), false)
})

test('G/H/I. QR + nome + VIP usam o MESMO contador', () => {
  let s = SESSAO_VAZIA
  s = registrarNaSessao(s, { resultado: 'LIBERADO', nome: 'QR', tipo: 'INGRESSO', horario: '21:00' })
  s = registrarNaSessao(s, {
    resultado: 'LIBERADO',
    nome: 'Nome',
    tipo: 'INGRESSO',
    horario: '21:01'
  })
  s = registrarNaSessao(s, { resultado: 'LIBERADO', nome: 'VIP', tipo: 'VIP', horario: '21:02' })
  assert.equal(s.total, 3)
})

test('J/K/L/M. ultima entrada guarda nome, tipo, codigo e horario', () => {
  const s = registrarNaSessao(SESSAO_VAZIA, {
    resultado: 'LIBERADO',
    nome: 'Maria Silva',
    tipo: 'INGRESSO',
    codigo: 'GZ123456',
    horario: '21:34'
  })
  assert.deepEqual(s.ultima, {
    nome: 'Maria Silva',
    tipo: 'INGRESSO',
    codigo: 'GZ123456',
    horario: '21:34'
  })

  const v = registrarNaSessao(SESSAO_VAZIA, {
    resultado: 'LIBERADO',
    nome: 'Joana',
    tipo: 'VIP',
    horario: '21:35'
  })
  assert.equal(v.ultima?.tipo, 'VIP')
  assert.equal(v.ultima?.codigo, null)

  assert.equal(formatarHorarioSessao(new Date(2026, 0, 1, 21, 34)), '21:34')
})

test('montarUltimaEntrada usa fallback seguro para nome vazio', () => {
  assert.equal(
    montarUltimaEntrada({ nome: '   ', tipo: 'INGRESSO', horario: '10:00' }).nome,
    'Entrada liberada'
  )
})

test('P. resultado nao-LIBERADO nao duplica contagem', () => {
  const s = { total: 1, ultima: null }
  const r = registrarNaSessao(s, {
    resultado: 'JA_UTILIZADO',
    nome: 'X',
    tipo: 'INGRESSO',
    horario: '10:00'
  })
  assert.equal(r.total, 1)
})

test('O. troca de evento zera a sessao; N. troca de modo nao', () => {
  assert.ok(gateApp.includes('watch(eventoId'))
  assert.ok(gateApp.includes('resetar()'))
  assert.ok(!gateApp.includes('watch(modo'))
})

test('Q. GateApp entrega total real ao GateHeader', () => {
  assert.ok(gateApp.includes(':total-entradas="total"'))
  assert.ok(gateApp.includes(':ultima="ultima"'))
  assert.ok(gateHeader.includes('props.totalEntradas'))
  assert.ok(gateHeader.includes('props.ultima'))
  assert.ok(gateHeader.includes('Entradas nesta sessão'))
  assert.ok(gateHeader.includes('Última entrada'))
})

test('R. cabecalho usa truncate/min-w-0 (sem overflow obvio)', () => {
  assert.ok(gateHeader.includes('truncate'))
  assert.ok(gateHeader.includes('min-w-0'))
  assert.ok(gateHeader.includes('max-w-full'))
})

test('contagem acontece no retorno da RPC (QR e nome)', () => {
  assert.ok(scanner.includes('registrar(resultado.value.resultado'))
  assert.ok(busca.includes('registrarSessao(resultado.value.resultado'))
})
