import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  filtrarVips,
  LIMITE_VIP_LOTE,
  mapearVipAdmin,
  mensagemErroVip,
  mensagemLoteVip,
  montarPayloadVip,
  parseNomesVip,
  resumoVips,
  rotuloStatusVip,
  statusVip,
  validarLoteVip,
  validarVip
} from '../app/utils/vip.ts'
import type { VipConvidado } from '../app/types/vip.ts'

function vip(overrides: Partial<VipConvidado> = {}): VipConvidado {
  return {
    vipId: 'v1',
    nome: 'Convidado',
    telefone: null,
    observacao: null,
    entrou: false,
    entradaEm: null,
    criadoEm: '2026-10-07T12:00:00Z',
    criadoPor: 'Admin',
    ...overrides
  }
}

test('statusVip e derivado da entrada', () => {
  assert.equal(statusVip(vip({ entrou: false })), 'AGUARDANDO')
  assert.equal(statusVip(vip({ entrou: true })), 'ENTROU')
  assert.equal(rotuloStatusVip('AGUARDANDO'), 'Aguardando')
  assert.equal(rotuloStatusVip('ENTROU'), 'Entrou')
})

test('mapearVipAdmin converte a linha real', () => {
  const item = mapearVipAdmin({
    vip_id: 'v1',
    nome: 'Maria',
    telefone: '11999990000',
    observacao: 'Mesa 4',
    entrou: true,
    entrada_em: '2026-10-07T22:00:00Z',
    criado_em: '2026-10-07T12:00:00Z',
    criado_por: 'Thiago'
  })
  assert.equal(item.vipId, 'v1')
  assert.equal(item.entrou, true)
  assert.equal(item.entradaEm, '2026-10-07T22:00:00Z')
  assert.equal(item.criadoPor, 'Thiago')
})

test('validarVip exige nome', () => {
  assert.ok(validarVip({ nome: '  ', telefone: '', observacao: '' }).nome)
  assert.deepEqual(validarVip({ nome: 'Ana', telefone: '', observacao: '' }), {})
})

test('montarPayloadVip normaliza vazios para null', () => {
  assert.deepEqual(montarPayloadVip({ nome: '  Ana  ', telefone: '   ', observacao: '' }), {
    nome: 'Ana',
    telefone: null,
    observacao: null
  })
  assert.deepEqual(montarPayloadVip({ nome: 'Ana', telefone: '11', observacao: 'obs' }), {
    nome: 'Ana',
    telefone: '11',
    observacao: 'obs'
  })
})

test('filtrarVips ignora acento e busca nome/telefone', () => {
  const lista = [
    vip({ vipId: 'v1', nome: 'João Silva' }),
    vip({ vipId: 'v2', nome: 'Maria Souza', telefone: '11988887777' })
  ]
  assert.equal(filtrarVips(lista, 'joao').length, 1)
  assert.equal(filtrarVips(lista, '1198888').length, 1)
  assert.equal(filtrarVips(lista, 'zzz').length, 0)
  assert.equal(filtrarVips(lista, '').length, 2)
})

test('resumoVips conta aguardando e entraram', () => {
  const lista = [vip({ entrou: true }), vip({ entrou: false }), vip({ entrou: false })]
  assert.deepEqual(resumoVips(lista), { total: 3, aguardando: 2, entraram: 1 })
})

test('mensagemErroVip traduz erros conhecidos', () => {
  assert.equal(
    mensagemErroVip({ code: '42501' }),
    'Você não tem permissão para gerenciar a lista VIP.'
  )
  assert.equal(
    mensagemErroVip({ message: 'Nao e possivel editar um convidado que ja registrou entrada' }),
    'O convidado já registrou entrada e não pode ser alterado.'
  )
  assert.equal(mensagemErroVip({ message: 'Informe o nome do convidado' }), 'Informe o nome do convidado.')
  assert.equal(mensagemErroVip(null), 'Não foi possível concluir a operação.')
})

// --- Cadastro em lote ---------------------------------------------------------

test('parseNomesVip separa por linha, faz trim e remove vazias', () => {
  const nomes = parseNomesVip('  João Silva \r\n\n Maria Souza\r\n   \nCarlos Ferreira  ')
  assert.deepEqual(nomes, ['João Silva', 'Maria Souza', 'Carlos Ferreira'])
  assert.deepEqual(parseNomesVip(''), [])
  assert.deepEqual(parseNomesVip('   \n  \n'), [])
})

test('parseNomesVip preserva acentos e duplicados', () => {
  const nomes = parseNomesVip('Ana\nAna\nJosé')
  assert.deepEqual(nomes, ['Ana', 'Ana', 'José'])
})

test('validarLoteVip rejeita vazio, excedente e nomes invalidos', () => {
  assert.equal(validarLoteVip([]), 'Informe pelo menos um nome.')
  assert.equal(
    validarLoteVip(Array(LIMITE_VIP_LOTE + 1).fill('Nome')),
    `Você pode adicionar até ${LIMITE_VIP_LOTE} convidados por vez.`
  )
  assert.equal(validarLoteVip(['Ok', '   ']), 'Há um nome inválido na lista.')
  assert.equal(validarLoteVip(['Ok', 'x'.repeat(121)]), 'Há um nome inválido na lista.')
})

test('validarLoteVip aceita exatamente o limite', () => {
  assert.equal(validarLoteVip(Array(LIMITE_VIP_LOTE).fill('Nome')), null)
  assert.equal(validarLoteVip(parseNomesVip('João\nMaria')), null)
})

test('mensagemLoteVip traduz erros conhecidos', () => {
  assert.equal(
    mensagemLoteVip({ code: '42501' }),
    'Você não tem permissão para gerenciar a lista VIP.'
  )
  assert.equal(
    mensagemLoteVip({ message: 'Informe pelo menos um nome' }),
    'Informe pelo menos um nome.'
  )
  assert.equal(
    mensagemLoteVip({ message: 'Limite de 100 convidados por inclusao excedido' }),
    `Você pode adicionar até ${LIMITE_VIP_LOTE} convidados por vez.`
  )
  assert.equal(
    mensagemLoteVip({ message: 'Ha um nome invalido na lista' }),
    'Há um nome inválido na lista.'
  )
  assert.equal(
    mensagemLoteVip(null),
    'Não foi possível adicionar os convidados.'
  )
})
