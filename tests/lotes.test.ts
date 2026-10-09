import assert from 'node:assert/strict'
import test from 'node:test'

import {
  mapearEventoLotesParaListItem,
  mapearLoteAdminParaListItem,
  mapearLoteParaFormulario,
  montarAtivacaoEm,
  proximaOrdem,
  vendasPermitemAtivacao,
  eventoPermiteAbrirVendas,
  ativacaoLoteBloqueada,
  type EventoLotesAdminRow,
  type LoteAdminRow
} from '../app/utils/lotes.ts'
import type { LotListItem } from '../app/types/lote.ts'

test('mapearLoteAdminParaListItem converte a linha real', () => {
  const row: LoteAdminRow = {
    lote_id: 'lote-1',
    nome: 'Lote 1',
    ordem: 1,
    quantidade: 10,
    preco: '50.00',
    tipo_ativacao: 'MANUAL',
    ativacao_em: null,
    ativado_em: '2026-10-29T23:00:00+00:00',
    encerrado_em: null,
    status: 'ATIVO',
    quantidade_vendida: 2,
    quantidade_disponivel: 8
  }
  const item = mapearLoteAdminParaListItem(row)
  assert.equal(item.id, 'lote-1')
  assert.equal(item.nome, 'Lote 1')
  assert.equal(item.preco, 50)
  assert.equal(item.ativacaoEm, null)
  assert.equal(item.ativadoEm, '2026-10-29T23:00:00+00:00')
  assert.equal(item.status, 'ATIVO')
  assert.equal(item.vendidos, 2)
  assert.equal(item.disponiveis, 8)
})

test('mapearEventoLotesParaListItem converte o cabecalho', () => {
  const row: EventoLotesAdminRow = {
    evento_id: 'evt-1',
    nome: 'Evento',
    status: 'AGENDADO',
    vendas_status: 'ABERTAS',
    publicacao_status: 'PUBLICADO',
    inicio_em: '2026-10-29T23:00:00+00:00',
    local: 'Galeria',
    imagem_url: 'https://cdn.exemplo.com/capa.jpg',
    capacidade_total: 500,
    estoque_antecipado: 100,
    vendidos: 2,
    disponiveis: 98
  }
  const evento = mapearEventoLotesParaListItem(row)
  assert.equal(evento.id, 'evt-1')
  assert.equal(evento.nome, 'Evento')
  assert.equal(evento.status, 'AGENDADO')
  assert.equal(evento.vendasStatus, 'ABERTAS')
  assert.equal(evento.publicacaoStatus, 'PUBLICADO')
  assert.equal(evento.inicioEm, '2026-10-29T23:00:00+00:00')
  assert.equal(evento.local, 'Galeria')
  assert.equal(evento.imagemUrl, 'https://cdn.exemplo.com/capa.jpg')
  assert.equal(evento.vendidos, 2)
  assert.equal(evento.disponiveis, 98)
})

test('mapearEventoLotesParaListItem descarta capa nao persistente (blob)', () => {
  const row: EventoLotesAdminRow = {
    evento_id: 'evt-2',
    nome: 'Evento Blob',
    status: 'AGENDADO',
    vendas_status: 'ENCERRADAS',
    publicacao_status: 'PUBLICADO',
    inicio_em: '2026-10-29T23:00:00+00:00',
    local: 'Galeria',
    imagem_url: 'blob:https://gz-1-ingressos.vercel.app/61108c56',
    capacidade_total: 100,
    estoque_antecipado: 50,
    vendidos: 0,
    disponiveis: 50
  }
  assert.equal(mapearEventoLotesParaListItem(row).imagemUrl, null)
})

test('montarAtivacaoEm interpreta America/Sao_Paulo e retorna instante UTC', () => {
  assert.equal(montarAtivacaoEm('2026-10-29', '20:00'), '2026-10-29T23:00:00.000Z')
  assert.equal(montarAtivacaoEm('2026-10-29', '09:30'), '2026-10-29T12:30:00.000Z')
  assert.equal(montarAtivacaoEm('2026-10-29', '00:00'), '2026-10-29T03:00:00.000Z')
  assert.equal(montarAtivacaoEm('2026-10-31', '23:30'), '2026-11-01T02:30:00.000Z')
  assert.equal(montarAtivacaoEm('', '20:00'), null)
  assert.equal(montarAtivacaoEm('2026-10-29', ''), null)
})

test('proximaOrdem calcula max+1', () => {
  assert.equal(proximaOrdem([]), 1)
  assert.equal(
    proximaOrdem([
      { id: 'a', eventoId: '', nome: 'L1', ordem: 1, quantidade: 1, preco: 1, tipoAtivacao: 'MANUAL', ativacaoEm: null, ativadoEm: null, encerradoEm: null, status: 'INATIVO', vendidos: 0, disponiveis: 1 },
      { id: 'b', eventoId: '', nome: 'L2', ordem: 3, quantidade: 1, preco: 1, tipoAtivacao: 'MANUAL', ativacaoEm: null, ativadoEm: null, encerradoEm: null, status: 'INATIVO', vendidos: 0, disponiveis: 1 }
    ]),
    4
  )
})

test('vendasPermitemAtivacao reflete a regra de dominio', () => {
  assert.equal(vendasPermitemAtivacao('ABERTAS'), true)
  assert.equal(vendasPermitemAtivacao('ENCERRADAS'), false)
})

test('eventoPermiteAbrirVendas', () => {
  assert.equal(eventoPermiteAbrirVendas('AGENDADO', 'ENCERRADAS'), true)
  assert.equal(eventoPermiteAbrirVendas('AGENDADO', 'ABERTAS'), false)
  assert.equal(eventoPermiteAbrirVendas('REALIZADO', 'ENCERRADAS'), false)
  assert.equal(eventoPermiteAbrirVendas('CANCELADO', 'ENCERRADAS'), false)
})

test('ativacaoLoteBloqueada', () => {
  assert.equal(ativacaoLoteBloqueada('INATIVO', 'ENCERRADAS'), true)
  assert.equal(ativacaoLoteBloqueada('INATIVO', 'ABERTAS'), false)
  assert.equal(ativacaoLoteBloqueada('ATIVO', 'ENCERRADAS'), false)
  assert.equal(ativacaoLoteBloqueada('ENCERRADO', 'ENCERRADAS'), false)
})

const loteBase: LotListItem = {
  id: 'l1',
  eventoId: 'e1',
  nome: 'Lote 1',
  ordem: 2,
  quantidade: 20,
  preco: 40,
  tipoAtivacao: 'DATA_HORA',
  ativacaoEm: '2026-10-29T23:00:00.000Z',
  ativadoEm: null,
  encerradoEm: null,
  status: 'INATIVO',
  vendidos: 5,
  disponiveis: 15
}

test('mapearLoteParaFormulario preenche o LotForm com data/hora em Sao Paulo', () => {
  const form = mapearLoteParaFormulario(loteBase)
  assert.equal(form.nome, 'Lote 1')
  assert.equal(form.ordem, 2)
  assert.equal(form.quantidade, 20)
  assert.equal(form.preco, 40)
  assert.equal(form.tipoAtivacao, 'DATA_HORA')
  assert.equal(form.dataAtivacao, '2026-10-29')
  assert.equal(form.horaAtivacao, '20:00')
  assert.equal(form.status, 'INATIVO')
})

test('mapearLoteParaFormulario sem ativacao_em deixa data/hora vazias', () => {
  const form = mapearLoteParaFormulario({ ...loteBase, tipoAtivacao: 'MANUAL', ativacaoEm: null })
  assert.equal(form.dataAtivacao, '')
  assert.equal(form.horaAtivacao, '')
})
