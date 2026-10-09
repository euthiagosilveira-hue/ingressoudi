import { test } from 'node:test'
import assert from 'node:assert/strict'

import { rotuloProvider, valorQrPix } from '../app/utils/pagamentos.ts'

test('rotuloProvider cobre Stone, Mercado Pago e Dinheiro', () => {
  assert.equal(rotuloProvider('STONE'), 'Stone')
  assert.equal(rotuloProvider('MERCADO_PAGO'), 'Mercado Pago')
  assert.equal(rotuloProvider('DINHEIRO'), 'Dinheiro')
})

test('valorQrPix usa exatamente o pix copia e cola', () => {
  const payload = '00020126580014BR.GOV.BCB.PIX0136abc-1235204000053039865802BR5913GZ1 INGRESSO6009SAO PAULO6304ABCD'
  assert.equal(valorQrPix({ pixCopyPaste: payload }), payload)
})

test('valorQrPix normaliza vazio para null', () => {
  assert.equal(valorQrPix(null), null)
  assert.equal(valorQrPix(undefined), null)
  assert.equal(valorQrPix({ pixCopyPaste: null }), null)
  assert.equal(valorQrPix({ pixCopyPaste: '   ' }), null)
})
