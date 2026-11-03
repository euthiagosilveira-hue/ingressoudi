import { test } from 'node:test'
import assert from 'node:assert/strict'

import { mapearResultadoEntradaRpc } from '../app/utils/gate.ts'
import { agruparLotesPorSetor, mapearSetorAdmin, proximoLoteInativo } from '../app/utils/lotes.ts'
import { eventoNoSetor, eventoTemSetores, nomeLoteSetor, rotaCheckoutSetor } from '../app/utils/setores.ts'
import type { LotListItem } from '../app/types/lote.ts'
import type { PublicEventDetail } from '../app/types/publicEvento.ts'

const eventoBase: PublicEventDetail = {
  eventoId: 'ev-1',
  slug: 'pagode',
  nome: 'Pagode',
  descricao: '',
  imagemUrl: null,
  inicioEm: '2026-11-20T23:00:00.000Z',
  local: 'Casa',
  endereco: 'Rua',
  status: 'AGENDADO',
  vendasStatus: 'ABERTAS',
  publicacaoStatus: 'PUBLICADO',
  loteId: 'lote-pista',
  loteNome: '1º lote',
  preco: 30,
  disponiveis: null,
  situacaoVenda: 'DISPONIVEL',
  organizacaoSlug: 'casa',
  setores: [
    { setorId: 's-pista', nome: 'Pista', ordem: 1, loteId: 'lote-pista', loteNome: '1º lote', preco: 30, situacaoVenda: 'DISPONIVEL' },
    { setorId: 's-cam', nome: 'Camarote', ordem: 2, loteId: 'lote-cam', loteNome: '1º lote', preco: 80, situacaoVenda: 'ESGOTADO' }
  ]
}

function lote(parcial: Partial<LotListItem>): LotListItem {
  return {
    id: 'x',
    eventoId: '',
    setorId: 's-pista',
    nome: 'Lote',
    ordem: 1,
    quantidade: 10,
    preco: 10,
    tipoAtivacao: 'MANUAL',
    ativacaoEm: null,
    ativadoEm: null,
    encerradoEm: null,
    status: 'INATIVO',
    vendidos: 0,
    disponiveis: 10,
    ...parcial
  }
}

test('eventoTemSetores: so com dois ou mais setores', () => {
  assert.equal(eventoTemSetores(eventoBase), true)
  assert.equal(eventoTemSetores({ setores: eventoBase.setores?.slice(0, 1) }), false)
  assert.equal(eventoTemSetores({ setores: undefined }), false)
})

test('eventoNoSetor: checkout usa lote, preco e situacao do setor', () => {
  const camarote = eventoNoSetor(eventoBase, 's-cam')
  assert.ok(camarote)
  assert.equal(camarote.setorId, 's-cam')
  assert.equal(camarote.setorNome, 'Camarote')
  assert.equal(camarote.loteId, 'lote-cam')
  assert.equal(camarote.loteNome, 'Camarote · 1º lote')
  assert.equal(camarote.preco, 80)
  assert.equal(camarote.situacaoVenda, 'ESGOTADO')
  assert.equal(eventoNoSetor(eventoBase, 'nao-existe'), null)
  assert.equal(eventoNoSetor(eventoBase, null), null)
})

test('nomeLoteSetor e rotaCheckoutSetor', () => {
  assert.equal(nomeLoteSetor({ nome: 'Pista', loteNome: '2º lote' }), 'Pista · 2º lote')
  assert.equal(nomeLoteSetor({ nome: 'Pista', loteNome: null }), 'Pista')
  assert.equal(rotaCheckoutSetor('casa', 'pagode', 's 1'), '/casa/pagode/comprar?setor=s%201')
})

test('agruparLotesPorSetor: grupos na ordem dos setores, lotes pela ordem', () => {
  const setores = [
    mapearSetorAdmin({ setor_id: 's-cam', nome: 'Camarote', ordem: 2, total_lotes: 1, quantidade: 5, vendidos: 1 }),
    mapearSetorAdmin({ setor_id: 's-pista', nome: 'Pista', ordem: 1 })
  ]
  const grupos = agruparLotesPorSetor(setores, [
    lote({ id: 'p2', ordem: 3 }),
    lote({ id: 'c1', ordem: 2, setorId: 's-cam' }),
    lote({ id: 'p1', ordem: 1 })
  ])
  assert.deepEqual(grupos.map((g) => g.setor.nome), ['Pista', 'Camarote'])
  assert.deepEqual(grupos[0]?.lotes.map((l) => l.id), ['p1', 'p2'])
  assert.deepEqual(grupos[1]?.lotes.map((l) => l.id), ['c1'])
  assert.equal(setores[1]?.totalLotes, 0)
})

test('proximoLoteInativo: so considera o mesmo setor', () => {
  const atual = lote({ id: 'p1', ordem: 1, status: 'ATIVO' })
  const lotes = [atual, lote({ id: 'c2', ordem: 2, setorId: 's-cam' }), lote({ id: 'p3', ordem: 3 })]
  assert.equal(proximoLoteInativo(lotes, atual)?.id, 'p3')
})

test('portaria: resultado traz o setor quando o banco envia', () => {
  const r = mapearResultadoEntradaRpc({ resultado: 'LIBERADO', ingresso_id: 'i', setor_nome: 'Camarote' })
  assert.equal(r.setorNome, 'Camarote')
  assert.equal(mapearResultadoEntradaRpc({ resultado: 'LIBERADO', setor_nome: null }).setorNome, null)
})
