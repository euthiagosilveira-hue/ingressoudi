import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  abertoComoApp,
  destinoAoAbrirApp,
  detectarPlataforma,
  deveMostrarInstalar,
  passosInstalacao
} from '../app/utils/instalarApp.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1'
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 Chrome/129.0 Mobile Safari/537.36'
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15'

test('detectarPlataforma reconhece iPhone, iPad, Android e computador', () => {
  assert.equal(detectarPlataforma({ userAgent: IPHONE }), 'ios')
  assert.equal(detectarPlataforma({ userAgent: MAC, maxTouchPoints: 5 }), 'ios')
  assert.equal(detectarPlataforma({ userAgent: MAC, maxTouchPoints: 0 }), 'outra')
  assert.equal(detectarPlataforma({ userAgent: ANDROID }), 'android')
  assert.equal(detectarPlataforma(null), 'outra')
})

test('abertoComoApp detecta tela cheia (Android) e standalone (iPhone)', () => {
  assert.equal(abertoComoApp({ standalone: true }), true)
  assert.equal(abertoComoApp({}, () => ({ matches: true })), true)
  assert.equal(abertoComoApp({}, () => ({ matches: false })), false)
  assert.equal(abertoComoApp({}, null), false)
  assert.equal(
    abertoComoApp({}, () => {
      throw new Error('sem suporte')
    }),
    false
  )
})

test('deveMostrarInstalar: nunca dentro do app, sim com convite nativo ou no celular', () => {
  assert.equal(deveMostrarInstalar({ instalado: true, conviteNativo: true, plataforma: 'android' }), false)
  assert.equal(deveMostrarInstalar({ instalado: false, conviteNativo: true, plataforma: 'outra' }), true)
  assert.equal(deveMostrarInstalar({ instalado: false, conviteNativo: false, plataforma: 'ios' }), true)
  assert.equal(deveMostrarInstalar({ instalado: false, conviteNativo: false, plataforma: 'android' }), true)
  assert.equal(deveMostrarInstalar({ instalado: false, conviteNativo: false, plataforma: 'outra' }), false)
})

test('passosInstalacao: iPhone usa Compartilhar, Android usa o menu', () => {
  assert.ok(passosInstalacao('ios').some((p) => p.texto.includes('Adicionar à Tela de Início')))
  assert.ok(passosInstalacao('android').some((p) => p.titulo === 'Instalar app'))
})

test('destinoAoAbrirApp: equipe vai ao painel/portaria, comprador aos ingressos', () => {
  assert.equal(destinoAoAbrirApp({ perfil: 'ADMINISTRADOR', ativo: true, temIngressosSalvos: true }), '/painel')
  assert.equal(destinoAoAbrirApp({ perfil: 'PORTARIA', ativo: true, temIngressosSalvos: false }), '/portaria')
  assert.equal(destinoAoAbrirApp({ perfil: 'ADMINISTRADOR', ativo: false, temIngressosSalvos: true }), '/recuperar-ingressos')
  assert.equal(destinoAoAbrirApp({ perfil: null, temIngressosSalvos: true }), '/recuperar-ingressos')
  assert.equal(destinoAoAbrirApp({ perfil: null, temIngressosSalvos: false }), '/')
})

test('manifesto: abre em /app, tela cheia, icones any e maskable e atalhos', () => {
  const manifesto = JSON.parse(ler('../public/site.webmanifest'))
  assert.equal(manifesto.start_url, '/app')
  assert.equal(manifesto.scope, '/')
  assert.equal(manifesto.display, 'standalone')
  const propositos = manifesto.icons.map((i: { purpose: string }) => i.purpose)
  assert.ok(propositos.includes('any'))
  assert.ok(propositos.includes('maskable'))
  assert.ok(manifesto.icons.some((i: { sizes: string }) => i.sizes === '512x512'))
  const atalhos = manifesto.shortcuts.map((a: { url: string }) => a.url)
  assert.deepEqual(atalhos, ['/recuperar-ingressos', '/portaria', '/painel'])
})

test('service worker so trata abertura de paginas e nao guarda dados em cache', () => {
  const sw = ler('../public/sw.js')
  assert.ok(sw.includes("req.mode !== 'navigate'"))
  assert.ok(sw.includes("'/offline.html'"))
  assert.ok(!sw.includes('cache.put'))
  assert.ok(ler('../public/offline.html').includes('Sem conexão'))
})

test('plugin registra o service worker so em producao e config nao deixa sw em cache', () => {
  const plugin = ler('../app/plugins/pwa.client.ts')
  assert.ok(plugin.includes('import.meta.dev'))
  assert.ok(plugin.includes("register('/sw.js'"))
  const config = ler('../nuxt.config.ts')
  assert.ok(config.includes("'/sw.js': { headers: { 'cache-control': 'no-cache' } }"))
  assert.ok(config.includes('apple-mobile-web-app-capable'))
})

test('botao Instalar app no painel, no rodape publico e na portaria', () => {
  assert.ok(ler('../app/components/AdminSidebar.vue').includes('<InstalarAppBotao variante="sidebar" />'))
  assert.ok(ler('../app/components/public/PublicFooter.vue').includes('<InstalarAppBotao variante="link" />'))
  assert.ok(ler('../app/components/portaria/GateHeader.vue').includes('<InstalarAppBotao />'))
})

test('pagina /app nao usa layout e decide o destino', () => {
  const pagina = ler('../app/pages/app.vue')
  assert.ok(pagina.includes('layout: false'))
  assert.ok(pagina.includes('destinoAoAbrirApp'))
  assert.ok(pagina.includes('lerPedidosSalvos'))
})
