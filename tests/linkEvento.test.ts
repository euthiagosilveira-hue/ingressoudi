import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import { copiarTexto, urlEventoPublico } from '../app/utils/linkEvento.ts'

test('urlEventoPublico monta o link completo da casa', () => {
  assert.equal(
    urlEventoPublico('https://www.ingressoudi.com.br/', 'casa-x', 'pagode-sexta'),
    'https://www.ingressoudi.com.br/casa-x/pagode-sexta'
  )
  assert.equal(
    urlEventoPublico('https://www.ingressoudi.com.br', null, 'pagode-sexta'),
    'https://www.ingressoudi.com.br/eventos/pagode-sexta'
  )
})

test('copiarTexto usa a Clipboard API quando disponivel', async () => {
  let copiado = ''
  const ok = await copiarTexto('https://x/y', { writeText: async (t) => { copiado = t } }, undefined)
  assert.equal(ok, true)
  assert.equal(copiado, 'https://x/y')
})

test('copiarTexto cai no execCommand quando a Clipboard API falha', async () => {
  const anexados: unknown[] = []
  let comando = ''
  const campo = { value: '', style: {}, setAttribute() {}, select() {} } as unknown as HTMLTextAreaElement
  const doc = {
    createElement: () => campo,
    body: {
      appendChild: (el: HTMLTextAreaElement) => anexados.push(el),
      removeChild: (el: HTMLTextAreaElement) => anexados.splice(anexados.indexOf(el), 1)
    },
    execCommand: (c: string) => { comando = c; return true }
  }
  const ok = await copiarTexto('https://x/y', { writeText: async () => { throw new Error('negado') } }, doc)
  assert.equal(ok, true)
  assert.equal(comando, 'copy')
  assert.equal(campo.value, 'https://x/y')
  assert.equal(anexados.length, 0)
})

test('copiarTexto retorna false sem nenhum meio de copiar', async () => {
  assert.equal(await copiarTexto('x', undefined, undefined), false)
})

test('botao Copiar link ligado no menu do evento e na pagina de lotes', () => {
  const menu = readFileSync(new URL('../app/components/eventos/EventCardActions.vue', import.meta.url), 'utf8')
  assert.match(menu, /selecionar\('copiar-link'\)/)
  const lista = readFileSync(new URL('../app/pages/eventos/index.vue', import.meta.url), 'utf8')
  assert.match(lista, /copiar-link/)
  assert.match(lista, /copiarLinkEvento/)
  const cabecalho = readFileSync(new URL('../app/components/lotes/LotEventHeader.vue', import.meta.url), 'utf8')
  assert.match(cabecalho, /copiarLinkEvento/)
})
