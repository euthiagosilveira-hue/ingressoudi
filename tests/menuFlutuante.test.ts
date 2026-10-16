import assert from 'node:assert/strict'
import test from 'node:test'

import { calcularPosicaoMenu } from '../app/utils/menuFlutuante.ts'

const janela = { largura: 1600, altura: 900 }
const menu = { largura: 208, altura: 120 }

test('menu abre abaixo e alinhado a direita do botao quando cabe', () => {
  const pos = calcularPosicaoMenu({ top: 100, bottom: 136, left: 1500, right: 1536 }, menu, janela)
  assert.deepEqual(pos, { top: 144, left: 1328 })
})

test('menu abre para cima quando nao cabe abaixo', () => {
  const pos = calcularPosicaoMenu({ top: 800, bottom: 836, left: 1500, right: 1536 }, menu, janela)
  assert.deepEqual(pos, { top: 672, left: 1328 })
})

test('menu nunca sai da janela pela esquerda nem por cima', () => {
  const pos = calcularPosicaoMenu({ top: 4, bottom: 40, left: 10, right: 46 }, menu, { largura: 400, altura: 140 })
  assert.equal(pos.left, 8)
  assert.ok(pos.top >= 8)
})
