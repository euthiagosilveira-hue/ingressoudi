import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  agruparEventosPorMes,
  seloSituacaoVitrine,
  textoQuantidadeEventos,
  urlVitrine
} from '../app/utils/vitrine.ts'

test('urlVitrine monta o link da casa e fica vazio sem slug', () => {
  assert.equal(urlVitrine('https://www.ingressoudi.com.br/', 'galeria-zero1'), 'https://www.ingressoudi.com.br/galeria-zero1')
  assert.equal(urlVitrine('', 'casa-x'), '/casa-x')
  assert.equal(urlVitrine('https://www.ingressoudi.com.br', null), '')
  assert.equal(urlVitrine('https://www.ingressoudi.com.br', '  '), '')
})

test('agruparEventosPorMes ordena e agrupa no fuso de Sao Paulo', () => {
  const grupos = agruparEventosPorMes([
    { nome: 'C', inicioEm: '2026-12-05T23:00:00Z' },
    { nome: 'A', inicioEm: '2026-11-10T22:00:00Z' },
    // 1/12 01:00 UTC = 30/11 22:00 em Sao Paulo
    { nome: 'B', inicioEm: '2026-12-01T01:00:00Z' }
  ])
  assert.deepEqual(
    grupos.map((g) => [g.chave, g.rotulo, g.eventos.map((e) => e.nome)]),
    [
      ['2026-11', 'Novembro de 2026', ['A', 'B']],
      ['2026-12', 'Dezembro de 2026', ['C']]
    ]
  )
})

test('agruparEventosPorMes manda data invalida para o fim e aceita lista vazia', () => {
  assert.deepEqual(agruparEventosPorMes([]), [])
  const grupos = agruparEventosPorMes([
    { nome: 'X', inicioEm: 'lixo' },
    { nome: 'A', inicioEm: '2027-01-10T22:00:00Z' }
  ])
  assert.deepEqual(grupos.map((g) => g.rotulo), ['Janeiro de 2027', 'Outras datas'])
})

test('seloSituacaoVitrine so marca o que nao esta a venda', () => {
  assert.equal(seloSituacaoVitrine('DISPONIVEL'), null)
  assert.equal(seloSituacaoVitrine('ESGOTADO'), 'Esgotado')
  assert.equal(seloSituacaoVitrine('SEM_LOTE'), 'Em breve')
  assert.equal(seloSituacaoVitrine('VENDAS_ENCERRADAS'), 'Vendas encerradas')
  assert.equal(seloSituacaoVitrine(null), null)
})

test('textoQuantidadeEventos', () => {
  assert.equal(textoQuantidadeEventos(0), 'Nenhum evento na agenda')
  assert.equal(textoQuantidadeEventos(1), '1 evento na agenda')
  assert.equal(textoQuantidadeEventos(4), '4 eventos na agenda')
})

test('vitrine usa a marca da casa, agrupa por mes e permite compartilhar', () => {
  const pagina = readFileSync(new URL('../app/pages/[organizacao]/index.vue', import.meta.url), 'utf8')
  assert.match(pagina, /agruparEventosPorMes/)
  assert.match(pagina, /var\(--cor-casa\)/)
  assert.match(pagina, /organizacao\.logoUrl/)
  assert.match(pagina, /Compartilhar/)
})

test('lista de eventos do admin mostra o link da vitrine', () => {
  const pagina = readFileSync(new URL('../app/pages/eventos/index.vue', import.meta.url), 'utf8')
  assert.match(pagina, /OrganizacaoVitrineLink/)
})
