import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import { avaliarCobrancaPix, type PixParaConferir } from '../server/services/payments/conferir-pix-regras.ts'
import type { PixCharge } from '../server/services/payments/payment-provider.ts'
import { resultadoPedeConferenciaPix } from '../app/utils/gate.ts'
import type { RegistrarEntradaQrResult } from '../app/types/gate.ts'

const pix: PixParaConferir = {
  pagamentoId: '11111111-1111-4111-8111-111111111111',
  organizacaoId: '22222222-2222-4222-8222-222222222222',
  cobrancaId: '123456',
  valor: '55.00'
}

function cobranca(parcial: Partial<PixCharge>): PixCharge {
  return {
    provider: 'MERCADO_PAGO',
    transactionId: '123456',
    chargeId: '123456',
    externalReference: pix.pagamentoId,
    status: 'APROVADO',
    pixCopyPaste: null,
    pixQrCode: null,
    expiresAt: null,
    amount: 55,
    ...parcial
  }
}

test('Pix aprovado, do mesmo pagamento e com o valor certo e confirmado', () => {
  assert.equal(avaliarCobrancaPix(cobranca({}), pix), 'CONFIRMAR')
})

test('Pix nao aprovado nao confirma', () => {
  assert.equal(avaliarCobrancaPix(cobranca({ status: 'PENDENTE' }), pix), 'NAO_PAGO')
  assert.equal(avaliarCobrancaPix(cobranca({ status: 'EXPIRADO' }), pix), 'NAO_PAGO')
})

test('Pix de outro pagamento ou com valor diferente nao confirma', () => {
  assert.equal(
    avaliarCobrancaPix(cobranca({ externalReference: '33333333-3333-4333-8333-333333333333' }), pix),
    'OUTRA_REFERENCIA'
  )
  assert.equal(avaliarCobrancaPix(cobranca({ amount: 50 }), pix), 'VALOR_DIVERGENTE')
  assert.equal(avaliarCobrancaPix(cobranca({ amount: null }), pix), 'VALOR_DIVERGENTE')
})

function resultado(parcial: Partial<RegistrarEntradaQrResult>): RegistrarEntradaQrResult {
  return {
    resultado: 'INVALIDO',
    ingressoId: '44444444-4444-4444-8444-444444444444',
    vipId: null,
    codigo: 'ABC',
    participanteNome: 'Fulano',
    entradaId: null,
    entradaEm: null,
    mensagem: 'Ingresso expirado',
    ...parcial
  }
}

test('portaria confere o Pix de ingresso expirado ou ainda nao pago', () => {
  assert.equal(resultadoPedeConferenciaPix(resultado({})), true)
  assert.equal(resultadoPedeConferenciaPix(resultado({ mensagem: 'Ingresso ainda nao pago' })), true)
})

test('portaria nao confere Pix nos outros resultados', () => {
  assert.equal(resultadoPedeConferenciaPix(resultado({ resultado: 'LIBERADO', mensagem: '' })), false)
  assert.equal(resultadoPedeConferenciaPix(resultado({ mensagem: 'Ingresso cancelado' })), false)
  assert.equal(resultadoPedeConferenciaPix(resultado({ resultado: 'JA_UTILIZADO', mensagem: 'Ingresso expirado' })), false)
  assert.equal(resultadoPedeConferenciaPix(resultado({ ingressoId: null })), false)
})

test('conferencia diaria agendada na Vercel antes da limpeza das 23h55', () => {
  const vercel = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'))
  const cron = vercel.crons.find((c: { path: string }) => c.path === '/api/cron/conferir-pix')
  assert.ok(cron)
  assert.equal(cron.schedule, '40 2 * * *')
})
