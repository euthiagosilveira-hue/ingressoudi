import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { situacaoPrazoDesistencia, temIngressoUtilizado } from '../app/utils/reembolso.ts'
import { MercadoPagoHttpError } from '../server/services/payments/mercado-pago/mercado-pago-client.ts'
import {
  detalheErroMp,
  erroJaReembolsado,
  mensagemErroReembolsoMp,
  reembolsarPagamentoMp,
  reembolsoAceito
} from '../server/services/payments/mercado-pago/mercado-pago-reembolso.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const agora = new Date('2026-10-15T12:00:00-03:00')

test('prazo de desistencia: 7 dias da compra e 48h antes do evento', () => {
  assert.equal(situacaoPrazoDesistencia('2026-10-12T12:00:00-03:00', '2026-10-25T22:00:00-03:00', agora).dentroDoPrazo, true)
  const velho = situacaoPrazoDesistencia('2026-10-01T12:00:00-03:00', '2026-10-25T22:00:00-03:00', agora)
  assert.equal(velho.dentroDoPrazo, false)
  assert.match(velho.motivo, /7 dias/)
  const perto = situacaoPrazoDesistencia('2026-10-14T12:00:00-03:00', '2026-10-16T22:00:00-03:00', agora)
  assert.equal(perto.dentroDoPrazo, false)
  assert.match(perto.motivo, /48 horas/)
  assert.equal(situacaoPrazoDesistencia(null, null, agora).dentroDoPrazo, false)
})

test('ingresso utilizado bloqueia o reembolso', () => {
  assert.equal(temIngressoUtilizado([{ status: 'VALIDO' }, { status: 'UTILIZADO' }]), true)
  assert.equal(temIngressoUtilizado([{ status: 'VALIDO' }]), false)
})

test('estorno no Mercado Pago: total, idempotente e com token da casa', async () => {
  let chamada: { url: string; init: RequestInit } | null = null
  const fetchFalso = (async (url: string, init: RequestInit) => {
    chamada = { url, init }
    return new Response(JSON.stringify({ id: 777, status: 'approved', amount: 23 }), { status: 201 })
  }) as unknown as typeof fetch
  const r = await reembolsarPagamentoMp('TOKEN-CASA', '123456', 'op-1', fetchFalso)
  assert.equal(r.id, 777)
  assert.ok(chamada)
  const c = chamada as unknown as { url: string; init: RequestInit }
  assert.equal(c.url, 'https://api.mercadopago.com/v1/payments/123456/refunds')
  assert.equal(c.init.method, 'POST')
  assert.equal(c.init.body, '{}')
  const h = c.init.headers as Record<string, string>
  assert.equal(h.Authorization, 'Bearer TOKEN-CASA')
  assert.equal(h['X-Idempotency-Key'], 'op-1')
})

test('erro do Mercado Pago vira MercadoPagoHttpError e mensagem amigavel', async () => {
  const fetchErro = (async () => new Response('{"message":"Insufficient balance"}', { status: 400 })) as unknown as typeof fetch
  await assert.rejects(() => reembolsarPagamentoMp('T', '1', 'k', fetchErro), (e: unknown) => {
    assert.ok(e instanceof MercadoPagoHttpError)
    assert.match(mensagemErroReembolsoMp(e), /não tem saldo disponível/)
    return true
  })
  assert.match(mensagemErroReembolsoMp(new MercadoPagoHttpError(401, 'unauthorized')), /Reconecte/)
  assert.match(mensagemErroReembolsoMp(new Error('rede')), /Tente novamente/)
  assert.equal(erroJaReembolsado(new MercadoPagoHttpError(400, '{"message":"Payment already refunded"}')), true)
  assert.equal(erroJaReembolsado(new MercadoPagoHttpError(400, '{"message":"outro"}')), false)
})

test('status do estorno aceito', () => {
  assert.equal(reembolsoAceito({ id: 1, status: 'approved' }), true)
  assert.equal(reembolsoAceito({ id: 1, status: 'in_process' }), true)
  assert.equal(reembolsoAceito({ id: 1, status: 'rejected' }), false)
})

test('rota de reembolso exige admin da organizacao e politica publicada', () => {
  const rota = ler('../server/api/admin/pedidos/[id]/reembolso.post.ts')
  assert.ok(rota.includes('exigirAdminOrganizacaoAtiva'))
  assert.ok(rota.includes("rpc('preparar_reembolso_pedido'"))
  assert.ok(rota.includes("rpc('concluir_reembolso_pedido'"))
  assert.ok(ler('../app/pages/reembolso.vue').includes('Política de reembolso'))
  assert.ok(ler('../app/components/public/PublicFooter.vue').includes('to="/reembolso"'))
  assert.ok(!ler('../app/components/pedidos/OrderDetails.vue').includes('(mock)'))
})

test('erro nao mapeado do Mercado Pago mostra o detalhe real', () => {
  const erro = new MercadoPagoHttpError(
    400,
    '{"message":"Invalid refund","error":"bad_request","status":400,"cause":[{"code":4040,"description":"amount invalid"}]}',
    'req-1'
  )
  assert.equal(detalheErroMp(erro), 'HTTP 400: Invalid refund | bad_request | 4040 amount invalid')
  const msg = mensagemErroReembolsoMp(erro)
  assert.match(msg, /Tente novamente/)
  assert.match(msg, /Detalhe do Mercado Pago: HTTP 400: Invalid refund/)
  assert.equal(detalheErroMp(new MercadoPagoHttpError(500, 'Internal error')), 'HTTP 500: Internal error')
  assert.equal(detalheErroMp(new Error('fetch failed')), 'fetch failed')
  assert.equal(detalheErroMp('x'), null)
  assert.ok(ler('../server/api/admin/pedidos/[id]/reembolso.post.ts').includes('detalhe: detalheErroMp(erro)'))
})

test('saldo indisponivel do vendedor (120065) vira mensagem de saldo', () => {
  const erro = new MercadoPagoHttpError(
    400,
    '{"message":"Collector hasn\'t enough available money","error":"bad_request","status":400,"cause":[{"code":120065,"description":"Collector hasn\'t enough available money"}]}'
  )
  assert.match(mensagemErroReembolsoMp(erro), /não tem saldo disponível/)
})
