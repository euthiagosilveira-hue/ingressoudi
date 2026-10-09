import { test } from 'node:test'
import assert from 'node:assert/strict'

import { normalizarCodigoPedido, normalizarTelefone } from '../app/utils/publicIngressos.ts'

test('normalizarCodigoPedido aplica trim e maiusculo', () => {
  assert.equal(normalizarCodigoPedido('  gz100123 '), 'GZ100123')
  assert.equal(normalizarCodigoPedido('GZ100123'), 'GZ100123')
  assert.equal(normalizarCodigoPedido(''), '')
})

test('normalizarTelefone mantem apenas digitos (aceita mascara)', () => {
  assert.equal(normalizarTelefone('(11) 99999-0000'), '11999990000')
  assert.equal(normalizarTelefone('11999990000'), '11999990000')
  assert.equal(normalizarTelefone('+55 11 9 9999-0000'), '5511999990000')
  assert.equal(normalizarTelefone(''), '')
})
