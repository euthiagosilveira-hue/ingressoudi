import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { PUBLIC_NAV_ITEMS } from '../app/utils/publicNav.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const header = ler('../app/components/public/PublicHeader.vue')
const layout = ler('../app/layouts/PublicLayout.vue')
const paginaEventos = ler('../app/pages/eventos-publicos.vue')
const paginaEvento = ler('../app/pages/eventos/[slug].vue')

test('A) header publico mostra "Meus ingressos"', () => {
  assert.ok(PUBLIC_NAV_ITEMS.some((item) => item.label === 'Meus ingressos'))
  assert.ok(header.includes('PUBLIC_NAV_ITEMS'))
})

test('B) clicar navega para /recuperar-ingressos e nunca para /meus-ingressos', () => {
  const item = PUBLIC_NAV_ITEMS.find((i) => i.label === 'Meus ingressos')
  assert.equal(item?.to, '/recuperar-ingressos')
  assert.ok(!PUBLIC_NAV_ITEMS.some((i) => i.to === '/meus-ingressos'))
  assert.ok(!PUBLIC_NAV_ITEMS.some((i) => i.to.startsWith('/meus-ingressos')))
})

test('C/D) item visivel em desktop e mobile (sem esconder/desabilitar)', () => {
  assert.ok(header.includes('v-for="item in PUBLIC_NAV_ITEMS"'))
  assert.ok(!header.includes('aria-disabled'))
  assert.ok(!header.includes('Disponível em breve'))
  assert.ok(!header.includes('hidden'))
})

test('E/F) paginas publicas usam o layout que renderiza o header', () => {
  assert.ok(layout.includes('<PublicHeader'))
  assert.ok(paginaEventos.includes("layout: 'public-layout'"))
  assert.ok(paginaEvento.includes("layout: 'public-layout'"))
})

test('G) navegacao nao expoe tokens e aponta para a validacao existente', () => {
  const serializado = JSON.stringify(PUBLIC_NAV_ITEMS)
  assert.ok(!/qr_token|checkout_token|recovery/i.test(serializado))
  assert.ok(PUBLIC_NAV_ITEMS.some((i) => i.to === '/recuperar-ingressos'))
})
