import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  MAX_PARCELAS,
  dividirNome,
  dividirTelefone,
  mensagemRecusaCartao,
  montarPayloadCartao,
  parcelasValidas,
  statusTentativa,
  type PedidoCartao
} from '../server/services/payments/mercado-pago/mercado-pago-cartao.ts'
import { mapMpPaymentToCharge } from '../server/services/payments/mercado-pago/mercado-pago-payments.ts'
import { mapearConfigCartao, rotuloFormaPagamento } from '../app/utils/cartaoCredito.ts'

const PEDIDO: PedidoCartao = {
  pagamentoId: 'pag-1',
  codigoPedido: 'IU100900',
  valorTotal: 62,
  valorTaxa: 2,
  eventoNome: 'Pagode do Berna',
  quantidade: 2,
  compradorNome: 'Maria da Silva Souza',
  compradorTelefone: '(34) 99999-1234',
  compradorEmail: 'maria@exemplo.com',
  notificationUrl: 'https://www.ingressoudi.com.br/api/webhooks/mercadopago?org=x'
}

const DADOS = {
  token: 'tok-123',
  paymentMethodId: 'master',
  issuerId: '24',
  installments: 3,
  payerEmail: 'maria@exemplo.com',
  identificationType: 'CPF',
  identificationNumber: '123.456.789-09'
}

test('payload do cartao usa valor e taxa do pedido, binary_mode e antifraude', () => {
  const p = montarPayloadCartao(PEDIDO, DADOS)
  assert.equal(p.transaction_amount, 62)
  assert.equal(p.application_fee, 2)
  assert.equal(p.installments, 3)
  assert.equal(p.binary_mode, true)
  assert.equal(p.external_reference, 'pag-1')
  assert.equal(p.issuer_id, 24)
  assert.equal(p.statement_descriptor, 'INGRESSOUDI')
  assert.deepEqual(p.payer.identification, { type: 'CPF', number: '12345678909' })
  assert.equal(p.payer.first_name, 'Maria')
  assert.equal(p.payer.last_name, 'da Silva Souza')
  assert.deepEqual(p.additional_info.payer.phone, { area_code: '34', number: '999991234' })
  assert.equal(p.additional_info.items[0]?.quantity, 2)
  assert.equal(p.additional_info.items[0]?.unit_price, 31)
  assert.equal(p.notification_url, PEDIDO.notificationUrl)
})

test('payload recusa parcelas fora do limite, dados faltando e taxa maior que o valor', () => {
  assert.throws(() => montarPayloadCartao(PEDIDO, { ...DADOS, installments: MAX_PARCELAS + 1 }))
  assert.throws(() => montarPayloadCartao(PEDIDO, { ...DADOS, installments: 0 }))
  assert.throws(() => montarPayloadCartao(PEDIDO, { ...DADOS, token: '' }))
  assert.throws(() => montarPayloadCartao({ ...PEDIDO, valorTaxa: 100 }, DADOS))
  assert.throws(() => montarPayloadCartao({ ...PEDIDO, compradorEmail: null }, { ...DADOS, payerEmail: 'x' }))
})

test('payload usa o e-mail do pedido quando o do formulario e invalido e omite taxa zero', () => {
  const p = montarPayloadCartao({ ...PEDIDO, valorTaxa: 0 }, { ...DADOS, payerEmail: '', issuerId: null })
  assert.equal(p.payer.email, 'maria@exemplo.com')
  assert.equal(p.application_fee, undefined)
  assert.equal(p.issuer_id, undefined)
})

test('helpers de parcelas, nome e telefone', () => {
  assert.equal(parcelasValidas('2'), 2)
  assert.equal(parcelasValidas(1.5), null)
  assert.deepEqual(dividirNome('  Ana  '), { first: 'Ana', last: '' })
  assert.deepEqual(dividirTelefone('+55 34 3333-4444'), { area_code: '34', number: '33334444' })
  assert.equal(dividirTelefone('1234'), null)
})

test('status da tentativa e mensagens de recusa', () => {
  assert.equal(statusTentativa('approved'), 'APROVADA')
  assert.equal(statusTentativa('rejected'), 'RECUSADA')
  assert.equal(statusTentativa('in_process'), 'PENDENTE')
  assert.match(mensagemRecusaCartao('cc_rejected_insufficient_amount'), /limite/)
  assert.match(mensagemRecusaCartao('cc_rejected_bad_filled_security_code'), /CVV/)
  assert.match(mensagemRecusaCartao('algo_novo'), /não foi aprovado/)
})

test('charge guarda status bruto para estorno e contestacao', () => {
  const c = mapMpPaymentToCharge({ id: 9, status: 'charged_back', status_detail: 'settled', payment_method_id: 'visa' })
  assert.equal(c.status, 'CANCELADO')
  assert.equal(c.providerStatus, 'charged_back')
  assert.equal(c.paymentMethodId, 'visa')
})

test('config publica do cartao e rotulo da forma de pagamento', () => {
  assert.equal(mapearConfigCartao({ disponivel: true, publicKey: 'APP_USR-1', valor: 10, maxParcelas: 3, tentativasRestantes: 5 }).disponivel, true)
  assert.equal(mapearConfigCartao({ disponivel: true, publicKey: '', valor: 10 }).disponivel, false)
  assert.equal(mapearConfigCartao(null).disponivel, false)
  assert.equal(rotuloFormaPagamento('PIX'), 'Pix')
  assert.equal(rotuloFormaPagamento('CARTAO', 3, 'master', '6351'), 'Cartão de crédito MASTER final 6351 em 3x')
  assert.equal(rotuloFormaPagamento('CARTAO', 1, null, null), 'Cartão de crédito à vista')
  assert.equal(rotuloFormaPagamento(null), null)
})

test('IP do comprador vai para o antifraude so quando valido', () => {
  const comIp = montarPayloadCartao({ ...PEDIDO, ipComprador: '177.10.20.30, 10.0.0.1' }, DADOS)
  assert.equal(comIp.additional_info.ip_address, '177.10.20.30')
  const semIp = montarPayloadCartao({ ...PEDIDO, ipComprador: '<script>' }, DADOS)
  assert.equal(semIp.additional_info.ip_address, undefined)
  assert.equal(montarPayloadCartao(PEDIDO, DADOS).additional_info.ip_address, undefined)
})
