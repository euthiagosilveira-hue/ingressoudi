import { test } from 'node:test'
import assert from 'node:assert/strict'

import { calcularValoresCheckout, taxaVisivelAoComprador } from '../app/utils/taxa.ts'

test('calcularValoresCheckout soma a taxa repassada por ingresso', () => {
  assert.deepEqual(calcularValoresCheckout(25, 2, 1.5), { valorIngressos: 50, valorTaxa: 3, total: 53 })
  assert.deepEqual(calcularValoresCheckout(25, 2, 0), { valorIngressos: 50, valorTaxa: 0, total: 50 })
  assert.deepEqual(calcularValoresCheckout(null, 3, 1), { valorIngressos: 0, valorTaxa: 3, total: 3 })
  assert.deepEqual(calcularValoresCheckout(19.9, 3, undefined), { valorIngressos: 59.7, valorTaxa: 0, total: 59.7 })
})

test('taxaVisivelAoComprador esconde taxa absorvida', () => {
  assert.equal(taxaVisivelAoComprador(3, true), 3)
  assert.equal(taxaVisivelAoComprador(3, undefined), 3)
  assert.equal(taxaVisivelAoComprador(3, false), 0)
  assert.equal(taxaVisivelAoComprador(undefined, true), 0)
})
