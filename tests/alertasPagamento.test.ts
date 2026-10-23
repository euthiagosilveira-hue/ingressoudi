import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

import { TITULOS_ERRO_PAGAMENTO, avisoErroPagamento } from '../server/utils/push-mensagens.ts'
import {
  ROTULOS_TIPO_ERRO,
  contarPorTipo,
  filtrarErrosPagamento,
  mapearErroPagamento,
  textoDetalhe
} from '../app/utils/errosPagamento.ts'

const ler = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8')

test('aviso de erro de pagamento leva para a tela de erros e cita a casa', () => {
  const aviso = avisoErroPagamento('PIX_CRIACAO', 'Bar do Zé', 'Mercado Pago recusou o Pix.')
  assert.equal(aviso.title, 'Falha ao gerar Pix')
  assert.equal(aviso.body, 'Bar do Zé: Mercado Pago recusou o Pix.')
  assert.equal(aviso.url, '/plataforma/erros-pagamento')
  assert.equal(aviso.tag, 'erro-pagamento-pix_criacao')
  assert.equal(avisoErroPagamento('WEBHOOK', null, 'Assinatura inválida').body, 'Assinatura inválida')
  assert.ok(avisoErroPagamento('REEMBOLSO', 'X', 'a'.repeat(400)).body.length <= 180)
})

test('tipos de erro iguais no servidor, na tela e no check do banco', () => {
  const migracao = ler('../supabase/migrations/20261023020000_alertas_erro_pagamento.sql')
  const tiposServidor = Object.keys(TITULOS_ERRO_PAGAMENTO).sort()
  assert.deepEqual(Object.keys(ROTULOS_TIPO_ERRO).sort(), tiposServidor)
  for (const tipo of tiposServidor) assert.ok(migracao.includes(`'${tipo}'`), tipo)
})

test('mapeia, filtra por periodo e tipo e conta por tipo', () => {
  const agora = Date.parse('2026-10-23T12:00:00Z')
  const erros = [
    { id: '1', tipo: 'PIX_CRIACAO', mensagem: 'a', criado_em: '2026-10-23T11:00:00Z', avisado: true, organizacao_nome: 'Casa' },
    { id: '2', tipo: 'PIX_CRIACAO', mensagem: 'b', criado_em: '2026-10-20T11:00:00Z', avisado: false, detalhe: { httpStatus: 500 } },
    { id: '3', tipo: 'REEMBOLSO', mensagem: 'c', criado_em: '2026-09-01T11:00:00Z', avisado: true, detalhe: [1] }
  ].map(mapearErroPagamento)
  assert.equal(erros[0]?.organizacaoNome, 'Casa')
  assert.equal(erros[1]?.organizacaoNome, null)
  assert.equal(erros[2]?.detalhe, null)

  assert.deepEqual(filtrarErrosPagamento(erros, { tipo: '', periodo: '24H' }, agora).map((e) => e.id), ['1'])
  assert.deepEqual(filtrarErrosPagamento(erros, { tipo: '', periodo: '7D' }, agora).map((e) => e.id), ['1', '2'])
  assert.deepEqual(filtrarErrosPagamento(erros, { tipo: 'REEMBOLSO', periodo: 'TODOS' }, agora).map((e) => e.id), ['3'])
  assert.deepEqual(contarPorTipo(erros), [
    { tipo: 'PIX_CRIACAO', total: 2 },
    { tipo: 'REEMBOLSO', total: 1 }
  ])
})

test('detalhe tecnico vira texto curto e ignora campos vazios', () => {
  assert.equal(textoDetalhe(null), null)
  assert.equal(textoDetalhe({ a: null, b: '' }), null)
  assert.equal(textoDetalhe({ httpStatus: 502, cause: [{ code: 1 }] }), 'httpStatus: 502 · cause: [{"code":1}]')
})

test('pontos de pagamento chamam o alerta', () => {
  const pontos: Array<[string, string[]]> = [
    ['../server/services/payments/payment-service.ts', ['PIX_CRIACAO', 'CONTA_MP_DESCONECTADA', 'TOKEN_MP', 'CONFIRMACAO', 'VALOR_DIVERGENTE']],
    ['../server/api/webhooks/mercadopago.post.ts', ['WEBHOOK', 'TOKEN_MP', 'CONFIRMACAO', 'VALOR_DIVERGENTE']],
    ['../server/api/payments/pix.post.ts', ['CONFIGURACAO', 'PIX_CRIACAO']],
    ['../server/api/mercadopago/oauth/callback.get.ts', ['OAUTH_MP', 'CONFIGURACAO']],
    ['../server/services/payments/mercado-pago/mercado-pago-conexao.ts', ['TOKEN_MP']],
    ['../server/api/admin/pedidos/[id]/reembolso.post.ts', ['REEMBOLSO']]
  ]
  for (const [arquivo, tipos] of pontos) {
    const fonte = ler(arquivo)
    assert.ok(fonte.includes('alertarErroPagamento'), arquivo)
    for (const tipo of tipos) assert.ok(fonte.includes(`tipo: '${tipo}'`), `${arquivo} ${tipo}`)
  }
})

test('alerta nunca derruba o pagamento e a tela entra no menu da plataforma', () => {
  const alerta = ler('../server/utils/alerta-pagamento.ts')
  assert.ok(alerta.includes('catch (e)'))
  assert.ok(ler('../app/components/AdminSidebar.vue').includes("to: '/plataforma/erros-pagamento'"))
  assert.ok(ler('../app/pages/plataforma/erros-pagamento.vue').includes("sidebarActive: 'Erros de pagamento'"))
})
