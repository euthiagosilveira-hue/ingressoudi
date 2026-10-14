import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { PUBLIC_NAV_ITEMS, itensNavegacaoPublica } from '../app/utils/publicNav.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const header = ler('../app/components/public/PublicHeader.vue')
const layout = ler('../app/layouts/PublicLayout.vue')
const paginaCasa = ler('../app/pages/[organizacao].vue')
const paginaInicial = ler('../app/pages/index.vue')

test('A) header publico mostra "Meus ingressos"', () => {
  assert.ok(PUBLIC_NAV_ITEMS.some((item) => item.label === 'Meus ingressos'))
  assert.ok(header.includes('itensNavegacaoPublica'))
})

test('B) clicar navega para /recuperar-ingressos e nunca para /meus-ingressos', () => {
  const item = PUBLIC_NAV_ITEMS.find((i) => i.label === 'Meus ingressos')
  assert.equal(item?.to, '/recuperar-ingressos')
  assert.ok(!PUBLIC_NAV_ITEMS.some((i) => i.to === '/meus-ingressos'))
  assert.ok(!PUBLIC_NAV_ITEMS.some((i) => i.to.startsWith('/meus-ingressos')))
})

test('C/D) item visivel em desktop e mobile (sem esconder/desabilitar)', () => {
  assert.ok(header.includes('v-for="item in navItems"'))
  assert.ok(!header.includes('aria-disabled'))
  assert.ok(!header.includes('Disponível em breve'))
  assert.ok(!header.includes('hidden'))
})

test('E/F) paginas publicas usam o layout que renderiza o header', () => {
  assert.ok(layout.includes('<PublicHeader'))
  assert.ok(paginaCasa.includes("layout: 'public-layout'"))
  assert.ok(paginaInicial.includes("layout: 'public-layout'"))
})

test('G) navegacao nao expoe tokens e aponta para a validacao existente', () => {
  const serializado = JSON.stringify(itensNavegacaoPublica('casa-x'))
  assert.ok(!/qr_token|checkout_token|recovery/i.test(serializado))
  assert.ok(PUBLIC_NAV_ITEMS.some((i) => i.to === '/recuperar-ingressos'))
})

test('H) "Eventos" leva ao catalogo da casa; sem casa, nao aparece', () => {
  assert.deepEqual(
    itensNavegacaoPublica('galeria-zero1').map((i) => i.to),
    ['/galeria-zero1', '/recuperar-ingressos']
  )
  assert.deepEqual(itensNavegacaoPublica(null).map((i) => i.to), ['/recuperar-ingressos'])
  assert.deepEqual(itensNavegacaoPublica('  ').map((i) => i.to), ['/recuperar-ingressos'])
})

test('I) header e footer nao tem marca de casa fixa no codigo', () => {
  const footer = ler('../app/components/public/PublicFooter.vue')
  assert.ok(!header.includes('Galeria Zero'))
  assert.ok(!footer.includes('Galeria Zero'))
  assert.ok(!header.includes('Logo horizontal'))
})
