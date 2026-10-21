import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  PAGINAS_SITEMAP,
  SITE_URL_PADRAO,
  dadosEstruturadosPlataforma,
  gerarSitemapXml,
  origemSite,
  urlAbsoluta,
  urlCanonica
} from '../app/utils/seo.ts'

test('origemSite usa o endereco oficial quando a variavel falta ou e invalida', () => {
  assert.equal(origemSite(''), SITE_URL_PADRAO)
  assert.equal(origemSite(undefined), SITE_URL_PADRAO)
  assert.equal(origemSite('nao-e-url'), SITE_URL_PADRAO)
  assert.equal(origemSite('https://exemplo.com.br/'), 'https://exemplo.com.br')
  assert.equal(origemSite('https://ingressoudi.vercel.app'), SITE_URL_PADRAO)
  assert.equal(origemSite('http://localhost:3000'), SITE_URL_PADRAO)
})

test('urlCanonica tira query, hash e barra final', () => {
  assert.equal(urlCanonica('', '/'), 'https://www.ingressoudi.com.br/')
  assert.equal(urlCanonica('', '/bar-do-samba/'), 'https://www.ingressoudi.com.br/bar-do-samba')
  assert.equal(urlCanonica('', '/bar-do-samba/show?utm=ig#topo'), 'https://www.ingressoudi.com.br/bar-do-samba/show')
  assert.equal(urlCanonica('https://ingressoudi.com.br', 'termos'), 'https://ingressoudi.com.br/termos')
})

test('urlAbsoluta mantem URL completa e completa caminho relativo', () => {
  assert.equal(urlAbsoluta('', '/og-image.png'), 'https://www.ingressoudi.com.br/og-image.png')
  assert.equal(urlAbsoluta('', 'https://cdn.exemplo.com/a.png'), 'https://cdn.exemplo.com/a.png')
})

test('sitemap lista as paginas publicas sem repetir', () => {
  const xml = gerarSitemapXml('', [...PAGINAS_SITEMAP, '/'])
  assert.match(xml, /^<\?xml version="1.0" encoding="UTF-8"\?>/)
  assert.equal((xml.match(/<loc>https:\/\/www\.ingressoudi\.com\.br\/<\/loc>/g) ?? []).length, 1)
  assert.match(xml, /<loc>https:\/\/www\.ingressoudi\.com\.br\/cadastro<\/loc>/)
  assert.ok(!xml.includes('/painel'))
})

test('sitemap escapa caracteres especiais', () => {
  assert.match(gerarSitemapXml('', ['/a&b']), /\/a&amp;b</)
})

test('dados estruturados descrevem a empresa e o site', () => {
  const dados = dadosEstruturadosPlataforma('') as { '@graph': Array<Record<string, unknown>> }
  assert.deepEqual(dados['@graph'].map((x) => x['@type']), ['Organization', 'WebSite'])
  assert.equal(dados['@graph'][0].name, 'Ingressoudi')
})

test('robots.txt aponta o sitemap e bloqueia as areas logadas', () => {
  const robots = readFileSync('public/robots.txt', 'utf8')
  assert.match(robots, /^Sitemap: https:\/\/www\.ingressoudi\.com\.br\/sitemap\.xml$/m)
  assert.match(robots, /^Disallow: \/painel\/$/m)
  assert.match(robots, /^Disallow: \/\*\/comprar$/m)
  assert.ok(!/^Disallow: \/$/m.test(robots))
})

test('html declara o idioma e as paginas publicas tem titulo para o Google', () => {
  assert.match(readFileSync('nuxt.config.ts', 'utf8'), /htmlAttrs: \{ lang: 'pt-BR' \}/)
  assert.match(readFileSync('app/app.vue', 'utf8'), /rel: 'canonical'/)
  assert.match(readFileSync('app/pages/index.vue', 'utf8'), /application\/ld\+json/)
  assert.match(readFileSync('app/pages/[organizacao]/[evento]/index.vue', 'utf8'), /ogImage/)
})
