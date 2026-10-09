import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  mapearDashboardEvento,
  mapearPedidosRecentes,
  mapearPagamentosPorStatus,
  mapearEntradasPorHora
} from '../app/utils/dashboard.ts'

const card = readFileSync(
  fileURLToPath(new URL('../app/components/TodayEventCard.vue', import.meta.url)),
  'utf8'
)

const EVENTO_BASE = {
  evento_id: 'e1',
  nome: 'Festa GZ1',
  slug: 'festa-gz1',
  imagem_url: 'https://cdn.exemplo.com/capa.jpg',
  inicio_em: '2026-10-03T23:00:00Z',
  local: 'Galeria Zero 1',
  status: 'AGENDADO'
}

test('mapearEntradasPorHora preserva hora/entradas', () => {
  const r = mapearEntradasPorHora([
    { hora: '18h', entradas: 3 },
    { hora: '19h', entradas: 0 }
  ])
  assert.equal(r.length, 2)
  assert.equal(r[0].hora, '18h')
  assert.equal(r[0].entradas, 3)
})

test('mapearPagamentosPorStatus atribui cores por key', () => {
  const r = mapearPagamentosPorStatus([
    { key: 'paid', label: 'Pago', value: 10 },
    { key: 'pending', label: 'Pendente', value: 2 },
    { key: 'canceled', label: 'Cancelado', value: 1 }
  ])
  assert.equal(r[0].color, '#22c55e')
  assert.equal(r[1].color, '#fbbf24')
  assert.equal(r[2].color, '#ef4444')
})

test('mapearDashboardEvento: EM_ANDAMENTO usa badge AO VIVO e capa real', () => {
  const r = mapearDashboardEvento({ ...EVENTO_BASE, status: 'EM_ANDAMENTO' })
  assert.equal(r.hasEvent, true)
  assert.equal(r.badge, 'AO VIVO')
  assert.equal(r.imageUrl, 'https://cdn.exemplo.com/capa.jpg')
  assert.equal(r.href, '/eventos/festa-gz1')
  assert.equal(r.title, 'Festa GZ1')
})

test('mapearDashboardEvento: proximo AGENDADO usa badge PROXIMO', () => {
  const r = mapearDashboardEvento({ ...EVENTO_BASE })
  assert.equal(r.hasEvent, true)
  assert.equal(r.badge, 'PRÓXIMO')
  assert.equal(r.date.length > 0, true)
  assert.equal(r.time.length > 0, true)
})

test('mapearDashboardEvento: sem evento -> estado vazio sem capa/href', () => {
  const r = mapearDashboardEvento(null)
  assert.equal(r.hasEvent, false)
  assert.equal(r.title, 'Nenhum próximo evento agendado.')
  assert.equal(r.imageUrl, null)
  assert.equal(r.href, '')
})

test('mapearDashboardEvento: imagem invalida cai no fallback (imageUrl null)', () => {
  assert.equal(mapearDashboardEvento({ ...EVENTO_BASE, imagem_url: null }).imageUrl, null)
  assert.equal(mapearDashboardEvento({ ...EVENTO_BASE, imagem_url: 'blob:xyz' }).imageUrl, null)
  assert.equal(
    mapearDashboardEvento({ ...EVENTO_BASE, imagem_url: 'data:image/png;base64,aaa' }).imageUrl,
    null
  )
  assert.equal(mapearDashboardEvento({ ...EVENTO_BASE, imagem_url: 'caminho/invalido' }).imageUrl, null)
})

test('mapearDashboardEvento: sem imagem mantem poster de fallback', () => {
  const r = mapearDashboardEvento({ ...EVENTO_BASE, imagem_url: null })
  assert.equal(r.imageUrl, null)
  assert.notEqual(r.poster.day, '')
  assert.equal(r.poster.name, 'Festa GZ1')
})

test('card: titulo "Próximo evento" (nao "Evento de hoje")', () => {
  assert.ok(card.includes('Próximo evento'))
  assert.ok(!card.toLowerCase().includes('evento de hoje'))
})

test('card: capa real com proporcao definida, object-cover e fallback', () => {
  assert.ok(card.includes('aspect-[3/4]'))
  assert.ok(card.includes('object-cover'))
  assert.ok(card.includes('object-center'))
  assert.ok(card.includes('@error="imagemOk = false"'))
  assert.ok(card.includes('Ver evento'))
})

test('card: usa a capa real quando ha imageUrl valida', () => {
  assert.ok(card.includes(':src="props.event.imageUrl'))
  assert.ok(card.includes('exibirCapa'))
})

test('card: poster de data permanece como fallback', () => {
  assert.ok(card.includes('poster.weekday'))
  assert.ok(card.includes('poster.day'))
  assert.ok(card.includes('poster.month'))
  assert.ok(card.includes('poster.name'))
})

test('card: preserva badge, nome, data, hora, local e botao alinhado', () => {
  assert.ok(card.includes('props.event.badge'))
  assert.ok(card.includes('props.event.title'))
  assert.ok(card.includes('props.event.date'))
  assert.ok(card.includes('props.event.time'))
  assert.ok(card.includes('props.event.venue'))
  assert.ok(card.includes('props.event.href'))
  assert.ok(card.includes('mt-auto'))
})

test('card: responsivo (aspect-video no mobile e capa lateral no >=sm)', () => {
  assert.ok(card.includes('aspect-video'))
  assert.ok(card.includes('sm:flex-row'))
  assert.ok(card.includes('sm:w-[38%]'))
})

test('mapearDashboardEvento: payload legado (sem imagem_url/evento_id) ainda mostra o card', () => {
  // Regressao do bug: a RPC antiga retorna chave 'id' e sem 'imagem_url'.
  const r = mapearDashboardEvento({
    id: 'e1',
    nome: 'PDC convida cantor Braga',
    slug: 'pdc-convida-cantor-braga',
    inicio_em: '2026-10-17T21:00:00Z',
    local: 'Galeria Zero 1',
    status: 'AGENDADO'
  } as never)
  assert.equal(r.hasEvent, true)
  assert.equal(r.imageUrl, null)
  assert.equal(r.badge, 'PRÓXIMO')
  assert.equal(r.href, '/eventos/pdc-convida-cantor-braga')
})

test('card: nao esconde o card por ausencia ou erro de imagem', () => {
  // A raiz depende apenas de hasEvent; a imagem so escolhe capa x poster.
  assert.ok(card.includes('v-if="props.event.hasEvent"'))
  assert.ok(card.includes('exibirCapa'))
  assert.ok(card.includes('@error="imagemOk = false"'))
})

test('mapearPedidosRecentes formata codigo/total/pagamento', () => {
  const r = mapearPedidosRecentes([
    {
      pedido_id: 'p1',
      codigo: 'GZ100700',
      buyer: 'Comprador Real',
      tickets: 2,
      total: '80.00',
      status: 'PAGO',
      criado_em: '2026-09-29T12:00:00Z',
      entrance_used: 1
    }
  ])
  assert.equal(r[0].id, '#GZ100700')
  assert.equal(r[0].buyer, 'Comprador Real')
  assert.equal(r[0].tickets, 2)
  assert.equal(r[0].payment, 'Pago')
  assert.equal(r[0].entranceUsed, 1)
  assert.equal(r[0].entranceTotal, 2)
  assert.match(r[0].total, /^R\$\s?80,00$/)
})
