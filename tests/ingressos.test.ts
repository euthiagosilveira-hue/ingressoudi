import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  mapearIngressoAdminParaDetalhe,
  mapearIngressoAdminParaListItem
} from '../app/utils/ingressos.ts'

const baseRow = {
  ingresso_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  codigo: 'GZ100300-01',
  participante_nome: 'Participante Alfa',
  status: 'VALIDO',
  valor_unitario: '40.00',
  utilizado_em: null,
  criado_em: '2026-09-29T11:59:00Z',
  pedido_id: 'p1p1p1p1-1111-2222-3333-444444444444',
  pedido_codigo: 'GZ100300',
  evento_id: 'e1e1e1e1-1111-2222-3333-444444444444',
  evento_nome: 'Evento Real',
  evento_inicio_em: '2026-10-25T19:19:10Z',
  lote_id: 'l1l1l1l1-1111-2222-3333-444444444444',
  lote_nome: 'Lote 1'
}

test('mapearIngressoAdminParaListItem adapta a linha real ao view-model', () => {
  const item = mapearIngressoAdminParaListItem(baseRow)
  assert.equal(item.codigo, 'GZ100300-01')
  assert.equal(item.participanteNome, 'Participante Alfa')
  assert.equal(item.status, 'VALIDO')
  assert.equal(item.valorUnitario, 40)
  assert.equal(item.pedidoCodigo, 'GZ100300')
  assert.equal(item.eventoNome, 'Evento Real')
  assert.equal(item.loteNome, 'Lote 1')
})

test('mapearIngressoAdminParaDetalhe monta detalhe e historico', () => {
  const det = mapearIngressoAdminParaDetalhe({
    ...baseRow,
    status: 'UTILIZADO',
    utilizado_em: '2026-09-29T12:00:00Z',
    pedido_status: 'PAGO',
    evento_local: 'Galeria Zero 1',
    entrada: { entrada_id: 'ent1', entrada_em: '2026-09-29T12:00:00Z', metodo: 'QR_CODE' }
  })

  assert.equal(det.pedidoStatus, 'PAGO')
  assert.equal(det.tipoPreco, 'LOTE')
  assert.equal(det.eventoLocal, 'Galeria Zero 1')
  assert.equal(det.qrMockValue.startsWith('DEMO-'), true)
  assert.equal(det.historico.some((h) => h.tipo === 'ENTRADA_REGISTRADA'), true)
})

test('detalhe de ingresso RESERVADO nao expoe entrada', () => {
  const det = mapearIngressoAdminParaDetalhe({
    ...baseRow,
    status: 'RESERVADO',
    pedido_status: 'RESERVADO',
    evento_local: null,
    entrada: null
  })
  assert.equal(det.status, 'RESERVADO')
  assert.equal(det.historico.some((h) => h.tipo === 'ENTRADA_REGISTRADA'), false)
})
