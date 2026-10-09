import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHmac } from 'node:crypto'

import {
  deveAutoAprovarPixTeste,
  deveConfirmarPagamento,
  deveExpirarReserva,
  deveIgnorarFalhaConfirmacao,
  mapMpOrderToCharge,
  mapMpStatus,
  montarPayloadOrderPix
} from '../server/services/payments/mercado-pago/mercado-pago-mapper.ts'
import {
  montarManifest,
  validarAssinaturaMp
} from '../server/services/payments/mercado-pago/mercado-pago-signature.ts'
import { MercadoPagoHttpError } from '../server/services/payments/mercado-pago/mercado-pago-client.ts'
import { sanitizarErroMercadoPago, serializarLogErroMercadoPago } from '../server/services/payments/mercado-pago/mercado-pago-error.ts'

test('mapMpStatus mapeia estados principais', () => {
  assert.equal(mapMpStatus('processed', 'accredited'), 'APROVADO')
  assert.equal(mapMpStatus('action_required', 'waiting_transfer'), 'PENDENTE')
  assert.equal(mapMpStatus('action_required', 'waiting_payment'), 'PENDENTE')
  assert.equal(mapMpStatus('expired', 'expired'), 'EXPIRADO')
  assert.equal(mapMpStatus('canceled', 'canceled'), 'CANCELADO')
  assert.equal(mapMpStatus('failed', 'high_risk'), 'REJEITADO')
  assert.equal(mapMpStatus('refunded', 'refunded'), 'REEMBOLSADO')
  assert.equal(mapMpStatus('processed', 'partially_refunded'), 'REEMBOLSADO')
})

test('mapMpOrderToCharge normaliza order Pix', () => {
  const charge = mapMpOrderToCharge({
    id: 'ORD123',
    status: 'action_required',
    status_detail: 'waiting_transfer',
    external_reference: 'pay-1',
    transactions: {
      payments: [
        {
          id: 'PAY1',
          status: 'action_required',
          status_detail: 'waiting_transfer',
          payment_method: { id: 'pix', type: 'bank_transfer', qr_code: 'EMV', qr_code_base64: 'B64' }
        }
      ]
    }
  })

  assert.equal(charge.provider, 'MERCADO_PAGO')
  assert.equal(charge.chargeId, 'ORD123')
  assert.equal(charge.transactionId, 'PAY1')
  assert.equal(charge.externalReference, 'pay-1')
  assert.equal(charge.pixCopyPaste, 'EMV')
  assert.equal(charge.pixQrCode, 'B64')
  assert.equal(charge.status, 'PENDENTE')
})

test('montarManifest segue o formato oficial e omite ausentes', () => {
  assert.equal(
    montarManifest({ xSignature: 'ts=123,v1=abc', xRequestId: 'req-1', dataId: 'ORD01ABC' }),
    'id:ord01abc;request-id:req-1;ts:123;'
  )
  assert.equal(
    montarManifest({ xSignature: 'ts=9,v1=x', xRequestId: null, dataId: 'AB' }),
    'id:ab;ts:9;'
  )
  assert.equal(montarManifest({ xSignature: null, xRequestId: null, dataId: 'AB' }), null)
})

test('validarAssinaturaMp aceita assinatura correta e rejeita invalida', () => {
  const secret = 'segredo-de-teste'
  const xRequestId = 'req-123'
  const dataId = 'ord01abc'
  const ts = '1742505638683'
  const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`
  const v1 = createHmac('sha256', secret).update(manifest).digest('hex')
  const header = `ts=${ts},v1=${v1}`

  assert.equal(validarAssinaturaMp({ xSignature: header, xRequestId, dataId }, secret), true)
  assert.equal(validarAssinaturaMp({ xSignature: header, xRequestId, dataId }, 'outro-segredo'), false)
  assert.equal(validarAssinaturaMp({ xSignature: 'ts=1,v1=deadbeef', xRequestId, dataId }, secret), false)
  assert.equal(validarAssinaturaMp({ xSignature: header, xRequestId, dataId }, ''), false)
})

function inputPix(autoApproveTestPix?: boolean) {
  return {
    amount: 40,
    externalReference: 'pay-1',
    payerEmail: 'test_user_br@testuser.com',
    expirationMinutes: 30,
    idempotencyKey: 'pay-1',
    autoApproveTestPix
  }
}

test('A) autoApproveTestPix=false/undefined nao envia first_name APRO', () => {
  assert.equal(montarPayloadOrderPix(inputPix(false)).payer.first_name, undefined)
  assert.equal(montarPayloadOrderPix(inputPix()).payer.first_name, undefined)
  assert.equal(montarPayloadOrderPix(inputPix(false)).payer.email, 'test_user_br@testuser.com')
})

test('B) autoApproveTestPix=true envia first_name=APRO', () => {
  const payload = montarPayloadOrderPix(inputPix(true))
  assert.equal(payload.payer.first_name, 'APRO')
  assert.equal(payload.payer.email, 'test_user_br@testuser.com')
  assert.equal(payload.total_amount, '40.00')
})

test('C) credencial de producao/nunca-teste nunca auto-aprova', () => {
  // credencial nao confirmada como teste => false mesmo com a flag ligada
  assert.equal(deveAutoAprovarPixTeste(true, false), false)
  assert.equal(deveAutoAprovarPixTeste(false, true), false)
  assert.equal(deveAutoAprovarPixTeste(false, false), false)
  assert.equal(deveAutoAprovarPixTeste(true, true), true)
  // e o payload so recebe APRO quando o resultado composto e verdadeiro
  const autoAprovar = deveAutoAprovarPixTeste(true, false)
  assert.equal(montarPayloadOrderPix(inputPix(autoAprovar)).payer.first_name, undefined)
})

test('A) provider nao-APROVADO nao chama confirmar_pagamento', () => {
  assert.equal(deveConfirmarPagamento('PENDENTE', 'PENDENTE'), false)
  assert.equal(deveConfirmarPagamento('EXPIRADO', 'PENDENTE'), false)
  assert.equal(deveConfirmarPagamento('REJEITADO', null), false)
  assert.equal(deveConfirmarPagamento('CANCELADO', 'PENDENTE'), false)
})

test('B) provider APROVADO + interno PENDENTE chama confirmar_pagamento', () => {
  assert.equal(deveConfirmarPagamento('APROVADO', 'PENDENTE'), true)
  assert.equal(deveConfirmarPagamento('APROVADO', null), true)
  assert.equal(deveConfirmarPagamento('APROVADO', undefined), true)
})

test('C) provider APROVADO + interno ja APROVADO e idempotente', () => {
  assert.equal(deveConfirmarPagamento('APROVADO', 'APROVADO'), false)
})

test('D) webhook e status concorrentes nao duplicam', () => {
  // 1a decisao confirma; apos confirmar o interno vira APROVADO e a 2a nao confirma.
  assert.equal(deveConfirmarPagamento('APROVADO', 'PENDENTE'), true)
  assert.equal(deveConfirmarPagamento('APROVADO', 'APROVADO'), false)
  // falha por corrida: se o interno ja esta APROVADO, ignora a falha
  assert.equal(deveIgnorarFalhaConfirmacao('APROVADO'), true)
})

test('E) falha na RPC de confirmacao vira erro controlado se nao aprovado', () => {
  assert.equal(deveIgnorarFalhaConfirmacao('PENDENTE'), false)
  assert.equal(deveIgnorarFalhaConfirmacao(null), false)
  assert.equal(deveIgnorarFalhaConfirmacao(undefined), false)
})

const AGORA = Date.parse('2026-10-01T15:00:00Z')

test('deveExpirarReserva: reserva vencida e nao aprovada expira', () => {
  assert.equal(
    deveExpirarReserva('2026-10-01T14:59:59Z', 'RESERVADO', 'PENDENTE', AGORA),
    true
  )
})

test('deveExpirarReserva: reserva ainda valida nao expira', () => {
  assert.equal(
    deveExpirarReserva('2026-10-01T15:30:00Z', 'RESERVADO', 'PENDENTE', AGORA),
    false
  )
})

test('deveExpirarReserva: pagamento aprovado no limite NUNCA expira', () => {
  assert.equal(
    deveExpirarReserva('2026-10-01T14:59:59Z', 'RESERVADO', 'APROVADO', AGORA),
    false
  )
})

test('deveExpirarReserva: pedido ja finalizado nao expira de novo', () => {
  assert.equal(deveExpirarReserva('2026-10-01T14:00:00Z', 'PAGO', 'APROVADO', AGORA), false)
  assert.equal(deveExpirarReserva('2026-10-01T14:00:00Z', 'EXPIRADO', 'EXPIRADO', AGORA), false)
  assert.equal(deveExpirarReserva('2026-10-01T14:00:00Z', 'CANCELADO', 'CANCELADO', AGORA), false)
})

test('deveExpirarReserva: dados ausentes/invalidos nao expiram', () => {
  assert.equal(deveExpirarReserva(null, 'RESERVADO', 'PENDENTE', AGORA), false)
  assert.equal(deveExpirarReserva('data-invalida', 'RESERVADO', 'PENDENTE', AGORA), false)
})

test('sanitizarErroMercadoPago extrai httpStatus/code/message/cause', () => {
  const corpo = JSON.stringify({
    message: 'The payer email is invalid',
    error: 'invalid_payer_email',
    status: 400,
    cause: [{ code: 'invalid_email', description: 'Email invalido' }]
  })
  const s = sanitizarErroMercadoPago(new MercadoPagoHttpError(400, corpo))
  assert.equal(s.httpStatus, 400)
  assert.equal(s.code, 'invalid_payer_email')
  assert.equal(s.message, 'The payer email is invalid')
  assert.deepEqual(s.cause, [{ code: 'invalid_email', description: 'Email invalido' }])
  assert.equal(s.errors, null)
})

test('serializarLogErroMercadoPago expande errors[].details e nao vaza secrets', () => {
  const corpo = JSON.stringify({
    errors: [
      {
        code: 'failed',
        message: 'As seguintes transações falharam',
        details: [
          {
            code: 'invalid_transaction',
            message: 'A chave PIX do vendedor nao existe',
            reason: 'pix_key_not_registered',
            authorization: 'Bearer SECRET_TOKEN_XYZ',
            access_token: 'APP_USR-SECRET'
          }
        ]
      }
    ]
  })
  const linha = serializarLogErroMercadoPago(
    {
      endpoint: 'POST /v1/orders',
      operation: 'createOrder',
      pagamentoId: 'pag-1',
      pedidoCodigo: 'GZ100154'
    },
    new MercadoPagoHttpError(402, corpo)
  )

  // e uma string serializada (nao objeto), com details expandido
  assert.equal(typeof linha, 'string')
  const parsed = JSON.parse(linha) as {
    httpStatus: number
    errors: Array<{ code: string; message: string; details: Array<Record<string, unknown>> }>
  }
  assert.equal(parsed.httpStatus, 402)
  assert.equal(parsed.errors[0].code, 'failed')
  assert.equal(parsed.errors[0].details.length, 1)
  assert.equal(parsed.errors[0].details[0].message, 'A chave PIX do vendedor nao existe')
  assert.equal(parsed.errors[0].details[0].reason, 'pix_key_not_registered')

  assert.ok(linha.includes('pix_key_not_registered'))
  assert.ok(!linha.includes('SECRET_TOKEN_XYZ'))
  assert.ok(!linha.includes('APP_USR-SECRET'))
  assert.ok(!linha.includes('authorization'))
  assert.ok(!linha.includes('access_token'))
})

test('sanitizarErroMercadoPago extrai errors de resposta HTTP 402', () => {
  const corpo = JSON.stringify({
    errors: [
      {
        code: 'invalid_transaction',
        message: 'Transaction could not be processed',
        description: 'The Pix key is not registered',
        type: 'processing_error',
        headers: { Authorization: 'Bearer SECRET_TOKEN_XYZ' },
        access_token: 'APP_USR-SECRET',
        details: [{ code: 'pix_key_missing', reason: 'Pix key not found' }]
      }
    ]
  })
  const s = sanitizarErroMercadoPago(new MercadoPagoHttpError(402, corpo))
  assert.equal(s.httpStatus, 402)
  assert.deepEqual(s.errors, [
    {
      code: 'invalid_transaction',
      message: 'Transaction could not be processed',
      description: 'The Pix key is not registered',
      type: 'processing_error',
      details: [{ code: 'pix_key_missing', reason: 'Pix key not found' }]
    }
  ])
  const serializado = JSON.stringify(s)
  assert.ok(!serializado.includes('SECRET_TOKEN_XYZ'))
  assert.ok(!serializado.includes('APP_USR-SECRET'))
  assert.ok(!serializado.includes('"headers"'))
  assert.ok(!serializado.includes('"access_token"'))
})

test('sanitizarErroMercadoPago lida com corpo nao-JSON e erro generico', () => {
  const texto = sanitizarErroMercadoPago(new MercadoPagoHttpError(500, 'erro interno do provedor'))
  assert.equal(texto.httpStatus, 500)
  assert.equal(texto.code, null)
  assert.equal(texto.message, 'erro interno do provedor')
  assert.equal(texto.cause, null)

  const generico = sanitizarErroMercadoPago(new Error('falha de rede'))
  assert.equal(generico.httpStatus, null)
})

test('sanitizarErroMercadoPago inclui requestId somente quando presente', () => {
  const comId = sanitizarErroMercadoPago(
    new MercadoPagoHttpError(402, JSON.stringify({ errors: [] }), 'REQ-BR-123')
  )
  assert.equal(comId.requestId, 'REQ-BR-123')

  const semId = sanitizarErroMercadoPago(new MercadoPagoHttpError(402, JSON.stringify({ errors: [] })))
  assert.equal(semId.requestId, null)
})

test('log expõe requestId e nenhum outro header/cookie', () => {
  const linha = serializarLogErroMercadoPago(
    {
      endpoint: 'POST /v1/orders',
      operation: 'createOrder',
      pagamentoId: 'pay-1',
      pedidoCodigo: 'GZ100155'
    },
    new MercadoPagoHttpError(402, JSON.stringify({ errors: [] }), 'REQ-9')
  )
  assert.ok(linha.includes('"requestId":"REQ-9"'))
  assert.ok(!linha.toLowerCase().includes('cookie'))
  assert.ok(!linha.toLowerCase().includes('set-cookie'))
  assert.ok(!linha.toLowerCase().includes('authorization'))
})

test('sanitizarErroMercadoPago nunca inclui headers/tokens/segredos', () => {
  const corpo = JSON.stringify({
    message: 'forbidden',
    error: 'unauthorized',
    status: 403,
    authorization: 'Bearer SECRET_TOKEN_XYZ',
    access_token: 'APP_USR-SECRET',
    headers: { Authorization: 'Bearer SECRET_TOKEN_XYZ' },
    cause: [{ code: 'policy', description: 'negado para APP_USR-SECRET' }]
  })
  const s = sanitizarErroMercadoPago(new MercadoPagoHttpError(403, corpo))
  assert.deepEqual(Object.keys(s).sort(), ['cause', 'code', 'errors', 'httpStatus', 'message', 'requestId'])
  assert.equal(s.httpStatus, 403)
  assert.equal(s.code, 'unauthorized')
  const serializado = JSON.stringify(s)
  assert.ok(!serializado.includes('SECRET_TOKEN_XYZ'))
  assert.ok(!serializado.includes('APP_USR-SECRET'))
  assert.ok(!serializado.includes('"authorization"'))
  assert.ok(!serializado.includes('"access_token"'))
  assert.ok(!serializado.includes('"headers"'))
})
