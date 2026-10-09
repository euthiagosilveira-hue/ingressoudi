import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  mapearFinanceiroResumo,
  mapearMovimentacaoParaListItem
} from '../app/utils/financeiro.ts'

test('mapearFinanceiroResumo converte numeros do RPC', () => {
  const resumo = mapearFinanceiroResumo({
    total: 4,
    aprovados: 1,
    valorAprovado: '40.00',
    pendente: '40.00',
    reembolsado: '40.00',
    liquido: '0.00'
  })
  assert.equal(resumo.valorAprovado, 40)
  assert.equal(resumo.pendente, 40)
  assert.equal(resumo.reembolsado, 40)
  assert.equal(resumo.liquido, 0)
  assert.equal(resumo.aprovados, 1)
})

test('mapearMovimentacaoParaListItem adapta a linha real', () => {
  const item = mapearMovimentacaoParaListItem({
    pagamento_id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    pedido_id: '11111111-1111-1111-1111-111111111111',
    pedido_codigo: 'GZ100600',
    evento_id: '22222222-2222-2222-2222-222222222222',
    evento_nome: 'Evento Real',
    comprador_nome: 'Comprador Real',
    provedor: 'MERCADO_PAGO',
    status: 'APROVADO',
    valor: '40.00',
    valor_reembolsado: null,
    transacao_id: 'PAY1',
    cobranca_id: 'ORD1',
    referencia_externa: 'ref1',
    expira_em: null,
    confirmado_em: '2026-09-29T12:00:00Z',
    cancelado_em: null,
    reembolsado_em: null,
    criado_em: '2026-09-29T11:59:00Z'
  })
  assert.equal(item.pedidoCodigo, 'GZ100600')
  assert.equal(item.provider, 'MERCADO_PAGO')
  assert.equal(item.status, 'APROVADO')
  assert.equal(item.valor, 40)
  assert.equal(item.valorReembolsado, 0)
  assert.equal(item.transactionId, 'PAY1')
})
