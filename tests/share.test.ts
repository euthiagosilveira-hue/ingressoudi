import { test } from 'node:test'
import assert from 'node:assert/strict'

import { montarShareData } from '../app/utils/share.ts'

test('montarShareData monta titulo/texto sem expor token', () => {
  const data = montarShareData({
    url: 'https://gz1.example/ingresso/abc123',
    eventoNome: 'Evento Teste'
  })
  assert.equal(data.title, 'GZ1 Ingresso')
  assert.equal(data.text, 'Seu ingresso para Evento Teste')
  assert.equal(data.url, 'https://gz1.example/ingresso/abc123')
})
