import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  descricaoConfirmacao,
  itemExigeConfirmacao,
  mascararTelefone,
  nomesAmbiguos,
  normalizarNomeBusca,
  precisaHintNome,
  rotuloOrigem
} from '../app/utils/portariaBusca.ts'
import { ingressoRegistravel } from '../app/utils/gate.ts'
import { registrarNaSessao, SESSAO_VAZIA } from '../app/utils/portariaSessao.ts'
import type { IngressoBuscaNome } from '../app/types/gate.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const painel = ler('../app/components/portaria/GateNameSearchPanel.vue')
const busca = ler('../app/composables/useGateNameSearch.ts')
const service = ler('../app/services/gate/ingressos.ts')

function item(over: Partial<IngressoBuscaNome> = {}): IngressoBuscaNome {
  return {
    origem: 'INGRESSO',
    ingressoId: 'i1',
    vipId: null,
    codigo: 'GZ100000-01',
    participanteNome: 'Maria Silva',
    status: 'VALIDO',
    utilizadoEm: null,
    entradaEm: null,
    telefone: null,
    ...over
  }
}

// A/B/C) hint do nome
test('A/B/C. hint aparece somente com 1 caractere util', () => {
  assert.equal(precisaHintNome(''), false)
  assert.equal(precisaHintNome('   '), false)
  assert.equal(precisaHintNome('a'), true)
  assert.equal(precisaHintNome(' ab '), false)
  assert.equal(precisaHintNome('Maria'), false)
})

// D) mascara de telefone
test('D. telefone e sempre mascarado', () => {
  assert.equal(mascararTelefone('34999991234'), '(34) *****-1234')
  assert.equal(mascararTelefone('99991234'), '*****-1234')
  assert.equal(mascararTelefone(''), '')
  assert.equal(mascararTelefone(null), '')
  assert.equal(mascararTelefone('12'), '')
  assert.ok(!mascararTelefone('34999991234').includes('999991234'))
})

// normalizacao
test('normalizarNomeBusca remove acento/caixa/espacos', () => {
  assert.equal(normalizarNomeBusca('  João   DA  Silva '), 'joao da silva')
})

// E/F/G/H) ambiguidade
test('E. resultado unico nao exige confirmacao', () => {
  assert.equal(itemExigeConfirmacao(item(), [item()]), false)
  assert.equal(itemExigeConfirmacao(item(), [item(), item({ participanteNome: 'João' })]), false)
})

test('F. dois resultados com o mesmo nome exigem confirmacao', () => {
  const lista = [item({ ingressoId: 'i1' }), item({ ingressoId: 'i2' })]
  assert.equal(itemExigeConfirmacao(lista[0], lista), true)
  assert.equal(nomesAmbiguos(lista).size, 1)
})

test('G. ingresso + VIP com o mesmo nome exigem confirmacao', () => {
  const lista = [
    item({ origem: 'INGRESSO' }),
    item({ origem: 'VIP', ingressoId: null, vipId: 'v1' })
  ]
  assert.equal(itemExigeConfirmacao(lista[1], lista), true)
})

test('H. nomes diferentes nao exigem confirmacao', () => {
  const lista = [
    item({ participanteNome: 'Maria Silva' }),
    item({ participanteNome: 'Maria Souza', ingressoId: 'i2' })
  ]
  assert.equal(itemExigeConfirmacao(lista[0], lista), false)
})

test('ambiguidade ignora acento/caixa', () => {
  const lista = [
    item({ participanteNome: 'João Silva' }),
    item({ participanteNome: ' joao   silva ', ingressoId: 'i2' })
  ]
  assert.equal(itemExigeConfirmacao(lista[0], lista), true)
})

// K) nao abrir fluxo para status nao registravel
test('K. UTILIZADO nao e registravel (nao abre confirmacao)', () => {
  assert.equal(ingressoRegistravel('UTILIZADO'), false)
  assert.equal(ingressoRegistravel('VALIDO'), true)
})

// I/J/R/S/P/Q) comportamento do componente (source)
test('I/J. Confirmar chama registrar uma vez; Cancelar nao chama', () => {
  assert.ok(painel.includes('function confirmarRegistro()'))
  assert.ok(/confirmarRegistro\(\)[\s\S]*?registrar\(item\)/.test(painel))
  assert.ok(/cancelarRegistro\(\)[\s\S]*?itemPendente\.value = null/.test(painel))
  assert.ok(!/cancelarRegistro\(\)[\s\S]*?registrar\(/.test(painel))
})

test('solicitarRegistro so abre confirmacao quando ambiguo', () => {
  assert.ok(painel.includes('if (ehAmbiguo(item))'))
  assert.ok(painel.includes('itemPendente.value = item'))
  assert.ok(painel.includes('void registrar(item)'))
})

test('L/M. VIP usa registrar_entrada_vip; ingresso usa registrar_entrada_nome', () => {
  assert.ok(service.includes("rpc('registrar_entrada_vip'"))
  assert.ok(service.includes("rpc('registrar_entrada_nome'"))
  assert.ok(busca.includes("ingresso.origem === 'VIP'"))
})

test('P/Q. botao Registrar com alvo >= 44px e desabilitado durante registro', () => {
  assert.ok(painel.includes('min-h-[44px]'))
  assert.ok(painel.includes('size="lg"'))
  assert.ok(painel.includes(':disabled="registrando"'))
})

test('R/S. nova busca limpa confirmacao e devolve foco ao campo', () => {
  assert.ok(/function novaBusca\(\)[\s\S]*?itemPendente\.value = null/.test(painel))
  assert.ok(painel.includes('inputNome.value?.focus()'))
  assert.ok(painel.includes('ref="inputNome"'))
})

test('dados exibidos: telefone mascarado, tipo e estado financeiro ausente', () => {
  assert.ok(painel.includes('mascararTelefone(item.telefone)'))
  assert.ok(painel.includes('rotuloOrigem'))
  assert.ok(painel.includes('Homônimo'))
  assert.ok(!painel.includes('valor_unitario'))
  assert.ok(!painel.includes('pagamento'))
})

test('N/O. sessao incrementa apenas em LIBERADO (Fase 2 preservada)', () => {
  const um = registrarNaSessao(SESSAO_VAZIA, {
    resultado: 'LIBERADO',
    nome: 'Maria',
    tipo: 'INGRESSO',
    horario: '21:00'
  })
  assert.equal(um.total, 1)
  const bloqueado = registrarNaSessao(um, {
    resultado: 'JA_UTILIZADO',
    nome: 'Maria',
    tipo: 'INGRESSO',
    horario: '21:01'
  })
  assert.equal(bloqueado.total, 1)
})

test('descricaoConfirmacao nao expoe telefone completo', () => {
  const texto = descricaoConfirmacao(
    item({ participanteNome: 'Maria', codigo: 'GZ1', telefone: '34999991234' })
  )
  assert.ok(texto.includes('Maria'))
  assert.ok(texto.includes('Ingresso'))
  assert.ok(texto.includes('GZ1'))
  assert.ok(texto.includes('*****-1234'))
  assert.ok(!texto.includes('34999991234'))
  assert.equal(rotuloOrigem('VIP'), 'VIP')
})
