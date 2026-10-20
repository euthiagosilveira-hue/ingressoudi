import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  assinarEstado,
  cifrarToken,
  decifrarToken,
  verificarEstado
} from '../server/utils/mercado-pago-cripto.ts'
import { montarUrlAutorizacao, precisaRenovar } from '../server/services/payments/mercado-pago/mercado-pago-oauth.ts'
import {
  fimReservaParaPix,
  isoBrasilia,
  mapMpPaymentStatus,
  mapMpPaymentToCharge,
  minutosValidadePix,
  montarNotificationUrl,
  montarPayloadPagamentoPix,
  valorConfere
} from '../server/services/payments/mercado-pago/mercado-pago-payments.ts'

const SEGREDO = 'chave-de-teste-com-mais-de-32-caracteres-123'
const ORG = '11111111-1111-4111-8111-111111111111'
const USR = '22222222-2222-4222-8222-222222222222'

test('cifrarToken/decifrarToken fazem ida e volta e nao expoem o texto', () => {
  const token = 'APP_USR-123456-abcdef'
  const cifrado = cifrarToken(token, SEGREDO)
  assert.ok(cifrado.startsWith('v1.'))
  assert.ok(!cifrado.includes(token))
  assert.notEqual(cifrarToken(token, SEGREDO), cifrado, 'IV aleatorio')
  assert.equal(decifrarToken(cifrado, SEGREDO), token)
})

test('decifrarToken falha com chave errada ou conteudo adulterado', () => {
  const cifrado = cifrarToken('segredo', SEGREDO)
  assert.throws(() => decifrarToken(cifrado, `${SEGREDO}-outra`))
  const partes = cifrado.split('.')
  partes[3] = Buffer.from('xxxx').toString('base64url')
  assert.throws(() => decifrarToken(partes.join('.'), SEGREDO))
  assert.throws(() => decifrarToken('formato-invalido', SEGREDO))
})

test('chave curta e rejeitada', () => {
  assert.throws(() => cifrarToken('x', 'curta'))
})

test('state assinado: valido, expirado e adulterado', () => {
  const agora = 1_800_000_000_000
  const estado = assinarEstado({ o: ORG, u: USR, e: agora + 60_000 }, SEGREDO)
  const ok = verificarEstado(estado, SEGREDO, agora)
  assert.equal(ok?.o, ORG)
  assert.equal(ok?.u, USR)

  assert.equal(verificarEstado(estado, SEGREDO, agora + 120_000), null, 'expirado')
  assert.equal(verificarEstado(estado, `${SEGREDO}-outra`, agora), null, 'outra chave')

  const [corpo, assinatura] = estado.split('.')
  const falso = Buffer.from(JSON.stringify({ o: 'outra-org', u: USR, e: agora + 60_000, n: 'x' })).toString('base64url')
  assert.equal(verificarEstado(`${falso}.${assinatura}`, SEGREDO, agora), null, 'corpo trocado')
  assert.equal(verificarEstado(corpo, SEGREDO, agora), null, 'sem assinatura')
  assert.equal(verificarEstado('', SEGREDO, agora), null)
})

test('montarUrlAutorizacao inclui os parametros do OAuth', () => {
  const url = new URL(
    montarUrlAutorizacao({ clientId: '123', redirectUri: 'https://app.exemplo.com/api/mercadopago/oauth/callback', state: 'abc' })
  )
  assert.equal(url.origin, 'https://auth.mercadopago.com')
  assert.equal(url.searchParams.get('client_id'), '123')
  assert.equal(url.searchParams.get('response_type'), 'code')
  assert.equal(url.searchParams.get('platform_id'), 'mp')
  assert.equal(url.searchParams.get('state'), 'abc')
  assert.equal(url.searchParams.get('redirect_uri'), 'https://app.exemplo.com/api/mercadopago/oauth/callback')
})

test('precisaRenovar so quando faltam menos de 7 dias', () => {
  const agora = Date.parse('2026-10-13T12:00:00Z')
  assert.equal(precisaRenovar(null, agora), false)
  assert.equal(precisaRenovar('2026-12-01T00:00:00Z', agora), false)
  assert.equal(precisaRenovar('2026-10-18T00:00:00Z', agora), true)
  assert.equal(precisaRenovar('2026-10-01T00:00:00Z', agora), true)
})

test('isoBrasilia usa -03:00', () => {
  assert.equal(isoBrasilia(Date.parse('2026-10-13T15:00:00.000Z')), '2026-10-13T12:00:00.000-03:00')
})

test('montarPayloadPagamentoPix: comissao, expiracao minima e notificacao', () => {
  const agora = Date.parse('2026-10-13T15:00:00.000Z')
  const payload = montarPayloadPagamentoPix(
    {
      amount: 53,
      applicationFee: 3,
      externalReference: 'pag-1',
      payerEmail: 'comprador@exemplo.com',
      expirationMinutes: 5,
      idempotencyKey: 'pag-1',
      description: 'Pedido ABC',
      notificationUrl: 'https://app.exemplo.com/api/webhooks/mercadopago?org=x'
    },
    agora
  )
  assert.equal(payload.transaction_amount, 53)
  assert.equal(payload.application_fee, 3)
  assert.equal(payload.payment_method_id, 'pix')
  assert.equal(payload.external_reference, 'pag-1')
  assert.equal(payload.description, 'Pedido ABC')
  assert.equal(payload.date_of_expiration, '2026-10-13T12:30:00.000-03:00')
  assert.equal(payload.notification_url, 'https://app.exemplo.com/api/webhooks/mercadopago?org=x')
  assert.equal(payload.payer.first_name, undefined)
})

test('montarPayloadPagamentoPix: sem comissao quando 0 e APRO em teste', () => {
  const payload = montarPayloadPagamentoPix(
    {
      amount: 25,
      applicationFee: 0,
      externalReference: 'pag-2',
      payerEmail: 'a@b.com',
      expirationMinutes: 45,
      idempotencyKey: 'pag-2',
      autoApproveTestPix: true
    },
    Date.parse('2026-10-13T15:00:00.000Z')
  )
  assert.equal('application_fee' in payload, false)
  assert.equal('notification_url' in payload, false)
  assert.equal(payload.payer.first_name, 'APRO')
  assert.equal(payload.date_of_expiration, '2026-10-13T12:45:00.000-03:00')
})

test('montarPayloadPagamentoPix: comissao maior que o valor e erro', () => {
  assert.throws(() =>
    montarPayloadPagamentoPix(
      { amount: 1, applicationFee: 2, externalReference: 'p', payerEmail: 'a@b.com', expirationMinutes: 30, idempotencyKey: 'p' },
      0
    )
  )
})

test('mapMpPaymentStatus cobre os estados da API de Payments', () => {
  assert.equal(mapMpPaymentStatus('approved', 'accredited'), 'APROVADO')
  assert.equal(mapMpPaymentStatus('pending', 'pending_waiting_transfer'), 'PENDENTE')
  assert.equal(mapMpPaymentStatus('in_process'), 'PENDENTE')
  assert.equal(mapMpPaymentStatus('rejected', 'cc_rejected_other_reason'), 'REJEITADO')
  assert.equal(mapMpPaymentStatus('cancelled', 'expired'), 'EXPIRADO')
  assert.equal(mapMpPaymentStatus('cancelled', 'by_collector'), 'CANCELADO')
  assert.equal(mapMpPaymentStatus('refunded', 'refunded'), 'REEMBOLSADO')
  assert.equal(mapMpPaymentStatus('charged_back'), 'CANCELADO')
})

test('mapMpPaymentToCharge normaliza o pagamento Pix', () => {
  const charge = mapMpPaymentToCharge({
    id: 123456789,
    status: 'pending',
    status_detail: 'pending_waiting_transfer',
    external_reference: 'pag-1',
    transaction_amount: 53,
    date_of_expiration: '2026-10-13T12:30:00.000-03:00',
    point_of_interaction: { transaction_data: { qr_code: '000201...', qr_code_base64: 'iVBOR...' } }
  })
  assert.equal(charge.provider, 'MERCADO_PAGO')
  assert.equal(charge.chargeId, '123456789')
  assert.equal(charge.transactionId, '123456789')
  assert.equal(charge.externalReference, 'pag-1')
  assert.equal(charge.status, 'PENDENTE')
  assert.equal(charge.pixCopyPaste, '000201...')
  assert.equal(charge.pixQrCode, 'iVBOR...')
  assert.equal(charge.amount, 53)
})

test('montarNotificationUrl so com https', () => {
  assert.equal(
    montarNotificationUrl('https://app.exemplo.com/', ORG),
    `https://app.exemplo.com/api/webhooks/mercadopago?org=${ORG}`
  )
  assert.equal(montarNotificationUrl('http://localhost:3000', ORG), undefined)
  assert.equal(montarNotificationUrl('', ORG), undefined)
})

test('valorConfere compara em centavos', () => {
  assert.equal(valorConfere(53, '53.00'), true)
  assert.equal(valorConfere(53.1, 53.1), true)
  assert.equal(valorConfere(52.99, '53.00'), false)
  assert.equal(valorConfere(null, 53), false)
  assert.equal(valorConfere(53, 'abc'), false)
})

test('validade do Pix nunca fica abaixo de 30 minutos', () => {
  assert.equal(minutosValidadePix(5), 30)
  assert.equal(minutosValidadePix(29.2), 30)
  assert.equal(minutosValidadePix(45.1), 46)
})

test('reserva termina depois do Pix, com folga', () => {
  const inicio = Date.parse('2026-10-20T12:00:00.000Z')
  assert.equal(fimReservaParaPix(inicio, 30), '2026-10-20T12:31:00.000Z')
  assert.equal(fimReservaParaPix(inicio, 30, 0), '2026-10-20T12:30:00.000Z')
})
