import assert from 'node:assert/strict'
import test from 'node:test'

import { imagemValida } from '../app/utils/imagem.ts'

test('imagemValida aceita http/https e caminho absoluto', () => {
  assert.equal(imagemValida('https://cdn.exemplo.com/capa.jpg'), 'https://cdn.exemplo.com/capa.jpg')
  assert.equal(imagemValida('http://cdn.exemplo.com/capa.png'), 'http://cdn.exemplo.com/capa.png')
  assert.equal(imagemValida('/mock/evento-1.svg'), '/mock/evento-1.svg')
})

test('imagemValida rejeita blob/data/vazio (nao persistem)', () => {
  assert.equal(imagemValida('blob:https://gz-1-ingressos.vercel.app/abc'), null)
  assert.equal(imagemValida('data:image/png;base64,AAAA'), null)
  assert.equal(imagemValida(''), null)
  assert.equal(imagemValida('   '), null)
  assert.equal(imagemValida(null), null)
  assert.equal(imagemValida(undefined), null)
  assert.equal(imagemValida('C:\\imagens\\capa.png'), null)
})
