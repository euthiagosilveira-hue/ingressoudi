import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  ARTIGOS_AJUDA,
  CATEGORIAS_AJUDA,
  artigosDaCategoria,
  artigosRelacionados,
  buscarArtigosAjuda,
  normalizarTextoAjuda,
  obterArtigoAjuda,
  partesTexto
} from '../app/utils/ajuda.ts'
import { PAGINAS_SITEMAP } from '../app/utils/seo.ts'

const publico = (nome: string) => fileURLToPath(new URL(`../public/ajuda/${nome}.webp`, import.meta.url))

test('cada artigo tem slug unico, categoria valida e pelo menos um passo', () => {
  const slugs = new Set<string>()
  const categorias = new Set(CATEGORIAS_AJUDA.map((c) => c.id))
  for (const artigo of ARTIGOS_AJUDA) {
    assert.ok(!slugs.has(artigo.slug), `slug repetido: ${artigo.slug}`)
    slugs.add(artigo.slug)
    assert.match(artigo.slug, /^[a-z0-9-]+$/)
    assert.ok(categorias.has(artigo.categoria), `categoria invalida em ${artigo.slug}`)
    assert.ok(artigo.passos.length > 0, `${artigo.slug} sem passos`)
  }
})

test('toda imagem citada existe em public/ajuda e tem texto alternativo', () => {
  for (const artigo of ARTIGOS_AJUDA) {
    for (const passo of artigo.passos) {
      if (!passo.imagem) continue
      assert.ok(existsSync(publico(passo.imagem)), `imagem ausente: ${passo.imagem}`)
      assert.ok(passo.alt && passo.alt.length > 5, `alt ausente: ${passo.imagem}`)
    }
  }
})

test('toda categoria tem artigos', () => {
  for (const categoria of CATEGORIAS_AJUDA) assert.ok(artigosDaCategoria(categoria.id).length > 0, categoria.id)
})

test('normaliza acentos e caixa', () => {
  assert.equal(normalizarTextoAjuda('  Meia-Entrada Cartão '), 'meia entrada cartao')
})

test('busca ignora acentos e prioriza o titulo', () => {
  assert.equal(buscarArtigosAjuda('portaria')[0]?.slug, 'validar-ingressos')
  assert.equal(buscarArtigosAjuda('mercado pago')[0]?.slug, 'conectar-mercado-pago')
  assert.ok(buscarArtigosAjuda('convite').some((a) => a.slug === 'convidar-equipe'))
  assert.ok(buscarArtigosAjuda('cartao').some((a) => a.slug === 'como-comprar'))
  assert.equal(buscarArtigosAjuda('lotes')[0]?.slug, 'setores-e-lotes')
})

test('busca ignora palavras vazias, aceita variacoes e consulta curta', () => {
  assert.deepEqual(buscarArtigosAjuda(''), [])
  assert.deepEqual(buscarArtigosAjuda('a'), [])
  assert.deepEqual(buscarArtigosAjuda('de como o'), [])
  assert.deepEqual(buscarArtigosAjuda('xyzinexistente'), [])
  assert.equal(buscarArtigosAjuda('pix nao confirmou')[0]?.slug, 'como-comprar')
  assert.equal(buscarArtigosAjuda('como convidar o porteiro')[0]?.slug, 'convidar-equipe')
  assert.ok(buscarArtigosAjuda('perdi meu ingresso').some((a) => a.slug === 'encontrar-ingressos'))
})

test('negrito vira partes sem html', () => {
  assert.deepEqual(partesTexto('Clique em **Salvar** agora'), [
    { texto: 'Clique em ', negrito: false },
    { texto: 'Salvar', negrito: true },
    { texto: ' agora', negrito: false }
  ])
  assert.deepEqual(partesTexto('<b>x</b>'), [{ texto: '<b>x</b>', negrito: false }])
})

test('relacionados nao repetem o proprio artigo', () => {
  const rel = artigosRelacionados('criar-conta')
  assert.ok(rel.length > 0)
  assert.ok(rel.every((a) => a.slug !== 'criar-conta'))
  assert.deepEqual(artigosRelacionados('nao-existe'), [])
  assert.equal(obterArtigoAjuda('nao-existe'), null)
})

test('a central de ajuda entra no sitemap', () => {
  assert.ok(PAGINAS_SITEMAP.includes('/ajuda'))
  for (const artigo of ARTIGOS_AJUDA) assert.ok(PAGINAS_SITEMAP.includes(`/ajuda/${artigo.slug}`))
})
