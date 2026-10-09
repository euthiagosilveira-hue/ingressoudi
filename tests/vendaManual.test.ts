import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ajustarParticipantes,
  calcularTotalVendaManual,
  loteSelecionado,
  mapearEventoVendaManual,
  mensagemErroVendaManual,
  montarPayloadVendaManual,
  normalizarValorMonetario,
  validarVendaManual,
  valorUnitarioEfetivo
} from '../app/utils/vendaManual.ts'
import type {
  EventoVendaManual,
  VendaManualForm,
  VendaManualLoteAtivo
} from '../app/types/vendaManual.ts'

const lote1: VendaManualLoteAtivo = { id: 'l1', nome: 'Lote 1', preco: 37.5, disponiveis: 5 }

function eventoBase(
  lotes: VendaManualLoteAtivo[] = [lote1],
  disponiveisEvento = 10
): EventoVendaManual {
  return {
    id: 'e1',
    nome: 'Evento Teste',
    inicioEm: '2026-10-25T19:00:00Z',
    local: 'Galeria',
    status: 'AGENDADO',
    disponiveisEvento,
    lotesAtivos: lotes,
    loteAtivo: lotes[0] ?? null
  }
}

function formBase(overrides: Partial<VendaManualForm> = {}): VendaManualForm {
  return {
    eventoId: 'e1',
    tipo: 'LOTE',
    loteId: 'l1',
    compradorNome: 'Maria',
    compradorTelefone: '11999990000',
    compradorEmail: '',
    quantidade: 2,
    valorUnitario: '',
    participantes: ['Maria', 'João'],
    ...overrides
  }
}

test('calcularTotalVendaManual multiplica preco por quantidade', () => {
  assert.equal(calcularTotalVendaManual(37.5, 2), 75)
  assert.equal(calcularTotalVendaManual(0.1, 3), 0.3)
  assert.equal(calcularTotalVendaManual(10, 0), 0)
  assert.equal(calcularTotalVendaManual(0, 5), 0)
})

test('normalizarValorMonetario aceita virgula e ponto', () => {
  assert.equal(normalizarValorMonetario('25'), 25)
  assert.equal(normalizarValorMonetario('25,50'), 25.5)
  assert.equal(normalizarValorMonetario('25.5'), 25.5)
  assert.equal(normalizarValorMonetario('1.234,56'), 1234.56)
  assert.equal(normalizarValorMonetario(''), 0)
  assert.equal(normalizarValorMonetario(null), 0)
})

test('ajustarParticipantes cresce com vazio e corta excedente', () => {
  assert.deepEqual(ajustarParticipantes([], 3, 'Maria'), ['Maria', '', ''])
  assert.deepEqual(ajustarParticipantes(['A', 'B', 'C'], 2, 'Maria'), ['A', 'B'])
})

test('mapearEventoVendaManual converte a linha real (lotes + disponibilidade global)', () => {
  const evento = mapearEventoVendaManual({
    evento_id: 'e1',
    nome: 'Festa',
    inicio_em: '2026-10-25T19:00:00Z',
    local: 'Galeria Zero',
    status: 'EM_ANDAMENTO',
    estoque_antecipado: 100,
    disponiveis_evento: 42,
    lotes_ativos: [
      { id: 'l1', nome: 'Lote 1', preco: '37.50', disponiveis: 5 },
      { id: 'l2', nome: 'Lote 2', preco: '50.00', disponiveis: 3 }
    ]
  })
  assert.equal(evento.status, 'EM_ANDAMENTO')
  assert.equal(evento.disponiveisEvento, 42)
  assert.equal(evento.lotesAtivos.length, 2)
  assert.equal(evento.loteAtivo?.id, 'l1')
  assert.equal(evento.lotesAtivos[1].preco, 50)
})

test('mapearEventoVendaManual trata ausencia de lote ativo', () => {
  const evento = mapearEventoVendaManual({
    evento_id: 'e1',
    nome: 'Festa',
    inicio_em: '2026-10-25T19:00:00Z',
    local: 'Galeria Zero',
    status: 'AGENDADO',
    estoque_antecipado: 100,
    disponiveis_evento: 10,
    lotes_ativos: null
  })
  assert.equal(evento.loteAtivo, null)
  assert.deepEqual(evento.lotesAtivos, [])
})

test('loteSelecionado e valorUnitarioEfetivo respeitam o modo', () => {
  const evento = eventoBase()
  assert.equal(loteSelecionado(formBase(), evento)?.id, 'l1')
  assert.equal(valorUnitarioEfetivo(formBase(), evento), 37.5)
  assert.equal(
    valorUnitarioEfetivo(formBase({ tipo: 'AVULSO', valorUnitario: '25,00' }), evento),
    25
  )
})

test('validarVendaManual aceita venda por lote com telefone vazio (opcional)', () => {
  const erros = validarVendaManual(
    formBase({ compradorTelefone: '' }),
    eventoBase()
  )
  assert.deepEqual(erros, {})
})

test('validarVendaManual aceita valor especial sem lote com telefone vazio', () => {
  const erros = validarVendaManual(
    formBase({ tipo: 'AVULSO', loteId: '', valorUnitario: '25', compradorTelefone: '' }),
    eventoBase([])
  )
  assert.deepEqual(erros, {})
})

test('validarVendaManual exige valor maior que zero no valor especial', () => {
  const evento = eventoBase()
  assert.ok(
    validarVendaManual(formBase({ tipo: 'AVULSO', loteId: '', valorUnitario: '0' }), evento)
      .valorUnitario
  )
  assert.ok(
    validarVendaManual(formBase({ tipo: 'AVULSO', loteId: '', valorUnitario: '' }), evento)
      .valorUnitario
  )
})

test('validarVendaManual exige lote ativo no modo lote', () => {
  assert.ok(
    validarVendaManual(formBase({ loteId: '' }), eventoBase()).loteId
  )
  assert.ok(
    validarVendaManual(formBase(), eventoBase([])).loteId
  )
})

test('validarVendaManual aponta evento e comprador obrigatorios', () => {
  const erros = validarVendaManual(
    formBase({ eventoId: '', compradorNome: '  ' }),
    null
  )
  assert.ok(erros.eventoId)
  assert.ok(erros.compradorNome)
})

test('validarVendaManual rejeita quantidade fora de 1..10', () => {
  const evento = eventoBase()
  assert.ok(validarVendaManual(formBase({ quantidade: 0, participantes: [] }), evento).quantidade)
  assert.ok(
    validarVendaManual(
      formBase({ quantidade: 11, participantes: Array(11).fill('P') }),
      evento
    ).quantidade
  )
})

test('validarVendaManual exige participantes e nomes nao vazios', () => {
  const evento = eventoBase()
  assert.ok(
    validarVendaManual(formBase({ quantidade: 2, participantes: ['Maria'] }), evento).participantes
  )
  assert.ok(
    validarVendaManual(formBase({ quantidade: 2, participantes: ['Maria', '  '] }), evento)
      .participantes
  )
})

test('montarPayloadVendaManual modo LOTE: lote preenchido, valor nulo, telefone nulo', () => {
  const payload = montarPayloadVendaManual(
    formBase({
      compradorNome: '  Maria  ',
      compradorTelefone: '   ',
      compradorEmail: '   ',
      quantidade: 1,
      participantes: ['  Maria  ', 'ignorado']
    })
  )
  assert.deepEqual(payload, {
    eventoId: 'e1',
    loteId: 'l1',
    compradorNome: 'Maria',
    compradorTelefone: null,
    compradorEmail: null,
    tipoPreco: 'LOTE',
    valorUnitario: null,
    participantes: ['Maria']
  })
})

test('montarPayloadVendaManual modo AVULSO: sem lote, com valor especial', () => {
  const payload = montarPayloadVendaManual(
    formBase({ tipo: 'AVULSO', loteId: 'l1', valorUnitario: '25,50', quantidade: 2 })
  )
  assert.equal(payload.loteId, null)
  assert.equal(payload.tipoPreco, 'AVULSO')
  assert.equal(payload.valorUnitario, 25.5)
})

test('mensagemErroVendaManual traduz permissao, estoque e valor', () => {
  assert.equal(
    mensagemErroVendaManual({ code: '42501', message: 'Permissao negada' }),
    'Você não tem permissão para registrar vendas manuais.'
  )
  assert.equal(
    mensagemErroVendaManual({ message: 'Estoque insuficiente no evento (disponivel=0, solicitado=1)' }),
    'Estoque insuficiente no evento.'
  )
  assert.equal(
    mensagemErroVendaManual({ message: 'Limite do lote insuficiente (disponivel=0, solicitado=1)' }),
    'Estoque insuficiente no lote selecionado.'
  )
  assert.equal(
    mensagemErroVendaManual({ message: 'Informe um valor unitario maior que zero' }),
    'Informe um valor unitário maior que zero.'
  )
  assert.equal(
    mensagemErroVendaManual({ message: 'Lote x nao esta ATIVO (status=INATIVO)' }),
    'O lote selecionado não está ativo.'
  )
  assert.equal(
    mensagemErroVendaManual({ code: '23514', message: 'algo' }),
    'Não foi possível concluir a venda. Verifique os dados informados.'
  )
  assert.equal(
    mensagemErroVendaManual(null),
    'Não foi possível registrar a venda manual.'
  )
})
