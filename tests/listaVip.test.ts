import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { classificarEventosVip, rotaVipEvento } from '../app/utils/listaVip.ts'
import { podeVerListaVip } from '../app/utils/navegacao.ts'
import type { AdminEventListItem } from '../app/types/evento.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

function evento(overrides: Partial<AdminEventListItem>): AdminEventListItem {
  return {
    eventoId: 'e1',
    nome: 'Evento',
    slug: 'evento',
    inicioEm: '2026-10-20T20:00:00-03:00',
    local: 'Galeria',
    status: 'AGENDADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'RASCUNHO',
    capacidadeTotal: 100,
    estoqueAntecipado: 100,
    publicadoEm: null,
    imagemUrl: null,
    loteAtivo: null,
    lotesCount: 0,
    pedidosCount: 0,
    ingressosCount: 0,
    ...overrides
  }
}

// A/B) Permissao no sidebar
test('podeVerListaVip: apenas ADMINISTRADOR', () => {
  assert.equal(podeVerListaVip('ADMINISTRADOR'), true)
  assert.equal(podeVerListaVip('PORTARIA'), false)
  assert.equal(podeVerListaVip(null), false)
})

// C) rota exige admin-auth
test('/lista-vip exige admin-auth', () => {
  const page = ler('../app/pages/lista-vip.vue')
  assert.ok(page.includes("middleware: ['admin-auth']"))
  assert.ok(page.includes("sidebarActive: 'Lista VIP'"))
  assert.ok(page.includes("title: 'Lista VIP'"))
})

// D/E/F/G) classificacao e ordenacao
test('classificarEventosVip: EM_ANDAMENTO primeiro e AGENDADOS por data', () => {
  const eventos = [
    evento({ eventoId: 'ag2', status: 'AGENDADO', inicioEm: '2026-11-10T20:00:00-03:00' }),
    evento({ eventoId: 'em1', status: 'EM_ANDAMENTO', inicioEm: '2026-10-21T20:00:00-03:00' }),
    evento({ eventoId: 'ag1', status: 'AGENDADO', inicioEm: '2026-10-25T20:00:00-03:00' }),
    evento({ eventoId: 'cx', status: 'CANCELADO', inicioEm: '2026-10-01T20:00:00-03:00' })
  ]
  const { operacionais } = classificarEventosVip(eventos)
  assert.deepEqual(
    operacionais.map((e) => e.eventoId),
    ['em1', 'ag1', 'ag2']
  )
})

test('classificarEventosVip: CANCELADO nao aparece e REALIZADO vai para historico', () => {
  const eventos = [
    evento({ eventoId: 'cancel', status: 'CANCELADO' }),
    evento({ eventoId: 'real1', status: 'REALIZADO', inicioEm: '2026-08-01T20:00:00-03:00' }),
    evento({ eventoId: 'real2', status: 'REALIZADO', inicioEm: '2026-09-01T20:00:00-03:00' }),
    evento({ eventoId: 'ag', status: 'AGENDADO', inicioEm: '2026-10-25T20:00:00-03:00' })
  ]
  const { operacionais, historicos } = classificarEventosVip(eventos)
  assert.deepEqual(operacionais.map((e) => e.eventoId), ['ag'])
  assert.deepEqual(historicos.map((e) => e.eventoId), ['real2', 'real1'])
  assert.equal(operacionais.some((e) => e.eventoId === 'cancel'), false)
})

test('classificarEventosVip: sem eventos elegiveis retorna vazio (empty state)', () => {
  const { operacionais, historicos } = classificarEventosVip([
    evento({ status: 'CANCELADO' })
  ])
  assert.equal(operacionais.length, 0)
  assert.equal(historicos.length, 0)
})

// H) rota de navegacao
test('rotaVipEvento aponta para a gestao canonica', () => {
  assert.equal(
    rotaVipEvento('21bfef22-15ab-437d-a657-c96ecb22b25f'),
    '/eventos/21bfef22-15ab-437d-a657-c96ecb22b25f/vip'
  )
})

// I) empty state na pagina
test('/lista-vip possui empty state com acao para eventos', () => {
  const page = ler('../app/pages/lista-vip.vue')
  assert.ok(page.includes('Nenhum evento disponível para Lista VIP.'))
  assert.ok(page.includes('to="/eventos"'))
})

// J) pagina de gestao continua existindo
test('gestao canonica /eventos/[id]/vip permanece', () => {
  const page = ler('../app/pages/eventos/[id]/vip.vue')
  assert.ok(page.includes("middleware: ['admin-auth']"))
})
