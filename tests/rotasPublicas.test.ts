import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ROTA_PAINEL,
  rotaCheckout,
  rotaEvento,
  rotaIngressosPedido,
  rotaOrganizacao,
  rotaPagamento,
  urlPublicaAbsoluta
} from '../app/utils/rotasPublicas.ts'
import { PLATAFORMA_NOME, tituloPublico } from '../app/utils/marca.ts'

test('rotas publicas por casa: /{casa}/{evento}', () => {
  assert.equal(rotaOrganizacao('galeria-zero1'), '/galeria-zero1')
  assert.equal(rotaEvento('galeria-zero1', 'pagode-sexta'), '/galeria-zero1/pagode-sexta')
  assert.equal(rotaCheckout('galeria-zero1', 'pagode-sexta'), '/galeria-zero1/pagode-sexta/comprar')
  assert.equal(
    rotaPagamento('galeria-zero1', 'pagode-sexta', 'tok-123'),
    '/galeria-zero1/pagode-sexta/comprar/pagamento?token=tok-123'
  )
  assert.equal(
    rotaIngressosPedido('galeria-zero1', 'pagode-sexta', 'tok-123'),
    '/galeria-zero1/pagode-sexta/comprar/ingressos?token=tok-123'
  )
})

test('sem casa, cai no formato legado (/eventos/...) que redireciona', () => {
  assert.equal(rotaOrganizacao(null), '/')
  assert.equal(rotaEvento(null, 'pagode-sexta'), '/eventos/pagode-sexta')
  assert.equal(rotaEvento('', 'pagode-sexta'), '/eventos/pagode-sexta')
  assert.equal(rotaCheckout(undefined, 'pagode-sexta'), '/eventos/pagode-sexta/comprar')
})

test('rotas escapam caracteres especiais', () => {
  assert.equal(rotaEvento('casa', 'a b'), '/casa/a%20b')
  assert.equal(rotaPagamento('casa', 'ev', 'a&b'), '/casa/ev/comprar/pagamento?token=a%26b')
})

test('painel do produtor sai da raiz', () => {
  assert.equal(ROTA_PAINEL, '/painel')
})

test('url absoluta para divulgacao', () => {
  assert.equal(urlPublicaAbsoluta('https://ingressoudi.vercel.app/', '/casa/ev'), 'https://ingressoudi.vercel.app/casa/ev')
  assert.equal(urlPublicaAbsoluta('', '/casa/ev'), '/casa/ev')
})

test('titulo publico usa a casa ou a marca da plataforma', () => {
  assert.equal(PLATAFORMA_NOME, 'Ingressoudi')
  assert.equal(tituloPublico('Pagamento', 'Galeria Zero 1'), 'Pagamento | Galeria Zero 1')
  assert.equal(tituloPublico('Pagamento'), 'Pagamento | Ingressoudi')
  assert.equal(tituloPublico(null, null), 'Ingressoudi')
})
