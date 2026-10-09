import { test } from 'node:test'
import assert from 'node:assert/strict'

import { mapearEventoAdminParaListItem, gerarSlug, montarInicioEm, separarInstanteSaoPaulo, mapearEventoAdminParaFormulario } from '../app/utils/eventos.ts'
import type { AdminEventDetail } from '../app/types/evento.ts'

test('mapearEventoAdminParaListItem adapta o item real para o shape dos cards', () => {
  const item = mapearEventoAdminParaListItem({
    eventoId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    nome: 'Evento Real',
    slug: 'evento-real',
    inicioEm: '2026-10-25T19:19:10.781Z',
    local: 'Galeria Zero 1',
    status: 'EM_ANDAMENTO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'PUBLICADO',
    capacidadeTotal: 200,
    estoqueAntecipado: 100,
    publicadoEm: '2026-09-01T00:00:00Z',
    imagemUrl: 'https://cdn.exemplo.com/capa.jpg',
    loteAtivo: { id: 'lote-1', nome: 'Lote 1', ordem: 1, preco: 40, quantidade: 150, vendidos: 132, disponiveis: 18 },
    lotesCount: 2,
    pedidosCount: 7,
    ingressosCount: 9
  })

  assert.equal(item.id, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
  assert.equal(item.nome, 'Evento Real')
  assert.equal(item.slug, 'evento-real')
  assert.equal(item.status, 'EM_ANDAMENTO')
  assert.equal(item.publicacaoStatus, 'PUBLICADO')
  assert.equal(item.vendasStatus, 'ENCERRADAS')
  assert.equal(item.vendidos, 9)
  assert.equal(item.imagemUrl, 'https://cdn.exemplo.com/capa.jpg')
  assert.deepEqual(item.loteAtual, { id: 'lote-1', nome: 'Lote 1', preco: 40 })
})

test('mapearEventoAdminParaListItem mantem "sem lote" quando nao ha ativo', () => {
  const item = mapearEventoAdminParaListItem({
    eventoId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    nome: 'Evento Sem Lote',
    slug: 'evento-sem-lote',
    inicioEm: '2026-10-25T19:19:10.781Z',
    local: 'Galeria Zero 1',
    status: 'AGENDADO',
    vendasStatus: 'ENCERRADAS',
    publicacaoStatus: 'RASCUNHO',
    capacidadeTotal: 200,
    estoqueAntecipado: 100,
    publicadoEm: null,
    imagemUrl: null,
    loteAtivo: null,
    lotesCount: 0,
    pedidosCount: 0,
    ingressosCount: 0
  })
  assert.equal(item.loteAtual, null)
})

test('mapearEventoAdminParaListItem usa fallback quando capa e invalida', () => {
  const base = {
    eventoId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    nome: 'Evento Real',
    slug: 'evento-real',
    inicioEm: '2026-10-25T19:19:10.781Z',
    local: 'Galeria Zero 1',
    status: 'AGENDADO' as const,
    vendasStatus: 'ABERTAS' as const,
    publicacaoStatus: 'PUBLICADO' as const,
    capacidadeTotal: 200,
    estoqueAntecipado: 100,
    publicadoEm: null,
    loteAtivo: null,
    lotesCount: 0,
    pedidosCount: 0,
    ingressosCount: 0
  }

  assert.equal(mapearEventoAdminParaListItem({ ...base, imagemUrl: null }).imagemUrl, null)
  assert.equal(
    mapearEventoAdminParaListItem({ ...base, imagemUrl: 'blob:https://gz-1-ingressos.vercel.app/x' }).imagemUrl,
    null
  )
  assert.equal(mapearEventoAdminParaListItem({ ...base, imagemUrl: 'C:\\capa.png' }).imagemUrl, null)
  assert.equal(
    mapearEventoAdminParaListItem({ ...base, imagemUrl: 'https://cdn.exemplo.com/x.jpg' }).imagemUrl,
    'https://cdn.exemplo.com/x.jpg'
  )
})

test('gerarSlug normaliza acentos/espacos/simbolos', () => {
  assert.equal(gerarSlug('Meu Evento Show!'), 'meu-evento-show')
  assert.equal(gerarSlug('  Banda  Conexão  '), 'banda-conexao')
  assert.equal(gerarSlug('Ação--2026'), 'acao-2026')
})

test('montarInicioEm interpreta America/Sao_Paulo e retorna instante UTC', () => {
  // A) 20:00 local (UTC-3) => 23:00Z
  assert.equal(montarInicioEm('2026-10-29', '20:00'), '2026-10-29T23:00:00.000Z')
  // B) horario da manha
  assert.equal(montarInicioEm('2026-10-29', '09:30'), '2026-10-29T12:30:00.000Z')
  // C) meia-noite local => 03:00Z
  assert.equal(montarInicioEm('2026-10-29', '00:00'), '2026-10-29T03:00:00.000Z')
  // D) virada de mes
  assert.equal(montarInicioEm('2026-10-31', '23:30'), '2026-11-01T02:30:00.000Z')
  // E) valor nao e ambiguo (contem Z)
  assert.equal(montarInicioEm('2026-10-29', '20:00').endsWith('Z'), true)
  // vazio
  assert.equal(montarInicioEm('', '20:00'), '')
  assert.equal(montarInicioEm('2026-10-29', ''), '')
})

test('separarInstanteSaoPaulo converte UTC para data/hora local', () => {
  assert.deepEqual(separarInstanteSaoPaulo('2026-10-29T23:00:00.000Z'), {
    data: '2026-10-29',
    hora: '20:00'
  })
  assert.deepEqual(separarInstanteSaoPaulo('2026-10-29T03:00:00.000Z'), {
    data: '2026-10-29',
    hora: '00:00'
  })
  assert.deepEqual(separarInstanteSaoPaulo('2026-11-01T02:30:00.000Z'), {
    data: '2026-10-31',
    hora: '23:30'
  })
  assert.deepEqual(separarInstanteSaoPaulo(''), { data: '', hora: '' })
})

const detalheBase: AdminEventDetail = {
  eventoId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  nome: 'PDC convida Cantor Braga',
  slug: 'pdc-convida-cantor-braga',
  descricao: 'Show',
  imagemUrl: 'https://cdn.exemplo.com/capa.jpg',
  inicioEm: '2026-10-29T23:00:00.000Z',
  encerradoEm: null,
  local: 'Galeria',
  endereco: 'Rua 1',
  capacidadeTotal: 350,
  estoqueAntecipado: 200,
  status: 'AGENDADO',
  vendasStatus: 'ENCERRADAS',
  publicacaoStatus: 'PUBLICADO',
  publicadoEm: '2026-10-01T00:00:00Z'
}

test('mapearEventoAdminParaFormulario preenche todos os campos', () => {
  const form = mapearEventoAdminParaFormulario(detalheBase)
  assert.equal(form.nome, 'PDC convida Cantor Braga')
  assert.equal(form.slug, 'pdc-convida-cantor-braga')
  assert.equal(form.descricao, 'Show')
  assert.equal(form.imagemUrl, 'https://cdn.exemplo.com/capa.jpg')
  assert.equal(form.dataInicio, '2026-10-29')
  assert.equal(form.horaInicio, '20:00')
  assert.equal(form.local, 'Galeria')
  assert.equal(form.endereco, 'Rua 1')
  assert.equal(form.capacidadeTotal, 350)
  assert.equal(form.estoqueAntecipado, 200)
  assert.equal(form.publicacaoStatus, 'PUBLICADO')
  assert.equal(form.vendasStatus, 'ENCERRADAS')
  assert.equal(form.status, 'AGENDADO')
})

test('mapearEventoAdminParaFormulario trata descricao nula e capa invalida', () => {
  const semCapa = mapearEventoAdminParaFormulario({
    ...detalheBase,
    descricao: null,
    imagemUrl: 'blob:https://gz-1-ingressos.vercel.app/abc'
  })
  assert.equal(semCapa.descricao, '')
  assert.equal(semCapa.imagemUrl, null)

  const semImagem = mapearEventoAdminParaFormulario({ ...detalheBase, imagemUrl: null })
  assert.equal(semImagem.imagemUrl, null)
})

test('round-trip: form -> instante preserva o horario', () => {
  const form = mapearEventoAdminParaFormulario(detalheBase)
  assert.equal(montarInicioEm(form.dataInicio, form.horaInicio), '2026-10-29T23:00:00.000Z')
})
