import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  casasDosEventos,
  filtrarEventosPlataforma,
  mapearEventoPlataforma,
  resumirEventosPlataforma
} from '../app/utils/eventosPlataforma.ts'

function linha(over: Record<string, unknown>) {
  return mapearEventoPlataforma({
    evento_id: 'e1',
    nome: 'Pagode de Sexta',
    slug: 'pagode-de-sexta',
    imagem_url: 'blob:abc',
    inicio_em: '2026-10-24T23:00:00+00:00',
    local: 'Casa do Samba',
    status: 'AGENDADO',
    vendas_status: 'ABERTAS',
    publicacao_status: 'PUBLICADO',
    criado_em: '2026-10-19T12:00:00+00:00',
    meia_entrada_ativa: true,
    organizacao_id: 'o1',
    organizacao_nome: 'Casa Um',
    organizacao_slug: 'casa-um',
    vendidos: 3,
    disponiveis: 97,
    pedidos_pagos: 2,
    valor_vendido: '75.50',
    taxa_plataforma: '4.50',
    lote_atual: { nome: '1º lote', preco: '25.00' },
    ...over
  })
}

test('mapearEventoPlataforma converte numeros e descarta imagem invalida', () => {
  const e = linha({})
  assert.equal(e.valorVendido, 75.5)
  assert.equal(e.taxaPlataforma, 4.5)
  assert.equal(e.imagemUrl, null)
  assert.equal(e.meiaEntradaAtiva, true)
  assert.deepEqual(e.loteAtual, { nome: '1º lote', preco: 25 })
  assert.equal(linha({ lote_atual: null }).loteAtual, null)
})

test('filtrarEventosPlataforma separa proximos e encerrados, por casa e busca', () => {
  const eventos = [
    linha({ evento_id: 'a', inicio_em: '2026-11-10T23:00:00Z' }),
    linha({ evento_id: 'b', inicio_em: '2026-10-25T23:00:00Z', status: 'EM_ANDAMENTO' }),
    linha({ evento_id: 'c', inicio_em: '2026-09-01T23:00:00Z', status: 'REALIZADO' }),
    linha({ evento_id: 'd', inicio_em: '2026-09-20T23:00:00Z', status: 'CANCELADO', organizacao_id: 'o2', organizacao_nome: 'Bar São João' })
  ]
  const base = { busca: '', organizacaoId: '', situacao: 'PROXIMOS' as const }
  assert.deepEqual(filtrarEventosPlataforma(eventos, base).map((e) => e.id), ['b', 'a'])
  assert.deepEqual(
    filtrarEventosPlataforma(eventos, { ...base, situacao: 'PASSADOS' }).map((e) => e.id),
    ['d', 'c']
  )
  assert.deepEqual(
    filtrarEventosPlataforma(eventos, { ...base, situacao: 'TODOS', organizacaoId: 'o2' }).map((e) => e.id),
    ['d']
  )
  assert.deepEqual(
    filtrarEventosPlataforma(eventos, { ...base, situacao: 'TODOS', busca: 'sao joao' }).map((e) => e.id),
    ['d']
  )
})

test('casasDosEventos e resumo da lista', () => {
  const eventos = [
    linha({ evento_id: 'a' }),
    linha({ evento_id: 'b', valor_vendido: 0.1, taxa_plataforma: 0.2 }),
    linha({ evento_id: 'c', organizacao_id: 'o2', organizacao_nome: 'Arena', vendidos: 10 })
  ]
  assert.deepEqual(casasDosEventos(eventos), [{ id: 'o2', nome: 'Arena' }, { id: 'o1', nome: 'Casa Um' }])
  const r = resumirEventosPlataforma(eventos)
  assert.equal(r.eventos, 3)
  assert.equal(r.casas, 2)
  assert.equal(r.ingressosVendidos, 16)
  assert.equal(r.valorVendido, 151.1)
  assert.equal(r.taxaPlataforma, 9.2)
})

test('pagina e menu do super admin ligados', () => {
  const sidebar = readFileSync(new URL('../app/components/AdminSidebar.vue', import.meta.url), 'utf8')
  assert.match(sidebar, /'\/plataforma\/eventos'/)
  assert.match(sidebar, /label: 'Todos os eventos'/)
  const pagina = readFileSync(new URL('../app/pages/plataforma/eventos.vue', import.meta.url), 'utf8')
  assert.match(pagina, /sidebarActive: 'Todos os eventos'/)
  assert.match(pagina, /listarEventosPlataforma/)
  assert.match(pagina, /ehSuperAdmin/)
  const migracao = readFileSync(
    new URL('../supabase/migrations/20261019000000_eventos_plataforma.sql', import.meta.url),
    'utf8'
  )
  assert.match(migracao, /usuario_e_super_admin\(\)/)
  assert.match(migracao, /revoke all on function public\.listar_eventos_plataforma\(\) from public, anon/)
})
