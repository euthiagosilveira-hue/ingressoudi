import { test } from 'node:test'
import assert from 'node:assert/strict'

import { mapearEntradaAdminParaListItem, estadoEntrada, resumoEntradas } from '../app/utils/entradas.ts'

const baseRow = {
  entrada_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  entrada_em: '2026-09-29T12:00:00Z',
  metodo: 'QR_CODE',
  anulada_em: null,
  anulada_por_nome: null,
  motivo_anulacao: null,
  ingresso_id: '11111111-1111-1111-1111-111111111111',
  ingresso_codigo: 'GZ100500-01',
  participante_nome: 'Participante Alfa',
  ingresso_status: 'UTILIZADO',
  pedido_id: '22222222-2222-2222-2222-222222222222',
  pedido_codigo: 'GZ100500',
  evento_id: '33333333-3333-3333-3333-333333333333',
  evento_nome: 'Evento Real',
  evento_inicio_em: '2026-09-29T11:00:00Z',
  operador_id: '44444444-4444-4444-4444-444444444444',
  operador_nome: 'Operador Portaria',
  criado_em: '2026-09-29T12:00:00Z'
}

test('mapearEntradaAdminParaListItem adapta a linha real', () => {
  const item = mapearEntradaAdminParaListItem(baseRow)
  assert.equal(item.id, baseRow.entrada_id)
  assert.equal(item.ingressoCodigo, 'GZ100500-01')
  assert.equal(item.participanteNome, 'Participante Alfa')
  assert.equal(item.pedidoCodigo, 'GZ100500')
  assert.equal(item.eventoNome, 'Evento Real')
  assert.equal(item.usuarioNome, 'Operador Portaria')
  assert.equal(item.metodo, 'QR_CODE')
  assert.equal(item.anuladaEm, null)
})

test('estadoEntrada deriva ATIVA/ANULADA de anulada_em', () => {
  assert.equal(estadoEntrada(mapearEntradaAdminParaListItem(baseRow)), 'ATIVA')
  const anulada = mapearEntradaAdminParaListItem({
    ...baseRow,
    anulada_em: '2026-09-29T13:00:00Z',
    anulada_por_nome: 'Admin',
    motivo_anulacao: 'teste'
  })
  assert.equal(estadoEntrada(anulada), 'ANULADA')
  assert.equal(anulada.anuladaPorUsuarioNome, 'Admin')
  assert.equal(anulada.motivoAnulacao, 'teste')
})

test('resumoEntradas conta total/ativas/anuladas/qr/nome', () => {
  const lista = [
    mapearEntradaAdminParaListItem(baseRow),
    mapearEntradaAdminParaListItem({ ...baseRow, entrada_id: 'b', metodo: 'NOME' }),
    mapearEntradaAdminParaListItem({ ...baseRow, entrada_id: 'c', anulada_em: '2026-09-29T13:00:00Z' })
  ]
  const resumo = resumoEntradas(lista)
  assert.equal(resumo.total, 3)
  assert.equal(resumo.ativas, 2)
  assert.equal(resumo.anuladas, 1)
  assert.equal(resumo.qrCode, 2)
  assert.equal(resumo.nome, 1)
})
