import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  formatarTelefone,
  mapearPedidoAdminParaDetalhe,
  mapearPedidoAdminParaListItem
} from '../app/utils/pedidos.ts'

test('formatarTelefone formata 11 e 10 digitos', () => {
  assert.equal(formatarTelefone('11999990000'), '(11) 99999-0000')
  assert.equal(formatarTelefone('1133334444'), '(11) 3333-4444')
  assert.equal(formatarTelefone(null), '')
})

test('mapearPedidoAdminParaListItem adapta a linha real ao view-model', () => {
  const item = mapearPedidoAdminParaListItem({
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    codigo: 'GZ100200',
    evento_id: 'e1e1e1e1-1111-2222-3333-444444444444',
    evento_nome: 'Evento Real',
    lote_id: null,
    lote_nome: null,
    comprador_nome: 'Comprador Real',
    comprador_telefone: '11999990000',
    comprador_email: 'c@test.local',
    quantidade: 2,
    tipo_preco: 'LOTE',
    valor_unitario: '40.00',
    valor_total: '80.00',
    status: 'PAGO',
    reserva_expira_em: null,
    pago_em: '2026-09-29T12:00:00Z',
    cancelado_em: null,
    criado_em: '2026-09-29T11:59:00Z',
    atualizado_em: null,
    motivo_valor_avulso: null,
    autorizado_por_nome: null,
    pagamento_status: 'APROVADO',
    pagamento_provedor: 'MERCADO_PAGO',
    pagamento_valor: '80.00'
  })

  assert.equal(item.codigo, 'GZ100200')
  assert.equal(item.eventoNome, 'Evento Real')
  assert.equal(item.telefone, '(11) 99999-0000')
  assert.equal(item.valorTotal, 80)
  assert.equal(item.tipoPreco, 'LOTE')
  assert.equal(item.status, 'PAGO')
  assert.equal(item.pagamentoProvedor, 'MERCADO_PAGO')
})

test('mapearPedidoAdminParaListItem expoe pagamento em DINHEIRO', () => {
  const item = mapearPedidoAdminParaListItem({
    id: 'ped-dinheiro',
    codigo: 'GZ100999',
    evento_id: 'e1',
    evento_nome: 'Evento',
    lote_id: 'l1',
    lote_nome: 'Lote',
    comprador_nome: 'Comprador',
    comprador_telefone: '11999990000',
    comprador_email: null,
    quantidade: 1,
    tipo_preco: 'LOTE',
    valor_unitario: '30.00',
    valor_total: '30.00',
    status: 'PAGO',
    reserva_expira_em: null,
    pago_em: '2026-10-07T12:00:00Z',
    cancelado_em: null,
    criado_em: '2026-10-07T12:00:00Z',
    atualizado_em: null,
    motivo_valor_avulso: null,
    autorizado_por_nome: null,
    pagamento_status: 'APROVADO',
    pagamento_provedor: 'DINHEIRO',
    pagamento_valor: '30.00'
  })

  assert.equal(item.pagamentoProvedor, 'DINHEIRO')
  assert.equal(item.valorTotal, 30)
  assert.equal(item.reservaExpiraEm, null)
})

test('mapearPedidoAdminParaDetalhe monta pagamento, ingressos e historico', () => {
  const det = mapearPedidoAdminParaDetalhe({
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    codigo: 'GZ100200',
    evento_id: 'e1e1e1e1-1111-2222-3333-444444444444',
    evento_nome: 'Evento Real',
    lote_id: null,
    lote_nome: null,
    comprador_nome: 'Comprador Real',
    comprador_telefone: '11999990000',
    comprador_email: 'c@test.local',
    quantidade: 1,
    tipo_preco: 'LOTE',
    valor_unitario: '40.00',
    valor_total: '40.00',
    status: 'PAGO',
    reserva_expira_em: null,
    pago_em: '2026-09-29T12:00:00Z',
    cancelado_em: null,
    criado_em: '2026-09-29T11:59:00Z',
    atualizado_em: '2026-09-29T12:00:00Z',
    motivo_valor_avulso: null,
    autorizado_por_nome: null,
    pagamento_status: 'APROVADO',
    pagamento_provedor: 'MERCADO_PAGO',
    pagamento_valor: '40.00',
    evento_inicio_em: '2026-10-25T19:19:10Z',
    evento_local: 'Galeria Zero 1',
    pagamento: {
      id: 'pg1',
      status: 'APROVADO',
      valor: '40.00',
      provedor: 'MERCADO_PAGO',
      transacao_id: 'PAY1',
      cobranca_id: 'ORD1',
      referencia_externa: 'ref1',
      expira_em: null,
      confirmado_em: '2026-09-29T12:00:00Z',
      cancelado_em: null,
      reembolsado_em: null,
      valor_reembolsado: 0
    },
    ingressos: [
      {
        id: 'i1',
        codigo: 'GZ100200-01',
        participante_nome: 'Comprador Real',
        valor_unitario: '40.00',
        status: 'VALIDO',
        utilizado_em: null
      }
    ]
  })

  assert.equal(det.pagamento?.status, 'APROVADO')
  assert.equal(det.pagamento?.provider, 'MERCADO_PAGO')
  assert.equal(det.ingressos.length, 1)
  assert.equal(det.ingressos[0].status, 'VALIDO')
  assert.equal(det.historico.some((h) => h.tipo === 'PAGAMENTO_APROVADO'), true)
  assert.equal(det.historico.some((h) => h.tipo === 'INGRESSOS_LIBERADOS'), true)
})

test('mapearPedidoAdminParaDetalhe preserva evento real (nome/data/local)', () => {
  const det = mapearPedidoAdminParaDetalhe({
    id: 'a',
    codigo: 'GZ100800',
    evento_id: 'e1e1e1e1-1111-2222-3333-444444444444',
    evento_nome: 'GZ1 Evento Teste Público',
    lote_id: null,
    lote_nome: null,
    comprador_nome: 'Comprador',
    comprador_telefone: '11999990000',
    comprador_email: null,
    quantidade: 1,
    tipo_preco: 'LOTE',
    valor_unitario: '40.00',
    valor_total: '40.00',
    status: 'PAGO',
    reserva_expira_em: null,
    pago_em: '2026-09-29T12:00:00Z',
    cancelado_em: null,
    criado_em: '2026-09-29T11:59:00Z',
    atualizado_em: null,
    motivo_valor_avulso: null,
    autorizado_por_nome: null,
    pagamento_status: 'APROVADO',
    pagamento_provedor: 'MERCADO_PAGO',
    pagamento_valor: '40.00',
    evento_inicio_em: '2026-10-25T19:19:10Z',
    evento_local: 'Galeria Zero 1',
    pagamento: null,
    ingressos: []
  })

  assert.equal(det.eventoId, 'e1e1e1e1-1111-2222-3333-444444444444')
  assert.equal(det.eventoNome, 'GZ1 Evento Teste Público')
  assert.equal(det.eventoInicioEm, '2026-10-25T19:19:10Z')
  assert.equal(det.eventoLocal, 'Galeria Zero 1')
})
