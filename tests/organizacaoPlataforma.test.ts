import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  eventoAtivo,
  filtrarEventosCasa,
  mapearDetalheCasa,
  percentual,
  repasseOnline,
  ticketMedio
} from '../app/utils/organizacaoPlataforma.ts'

function evento(over: Record<string, unknown> = {}) {
  return {
    evento_id: 'ev-1',
    nome: 'Show',
    slug: 'show',
    inicio_em: '2026-11-15T22:00:00Z',
    local: 'Casa',
    status: 'AGENDADO',
    publicacao_status: 'PUBLICADO',
    vendas_status: 'ABERTAS',
    capacidade_total: 250,
    vendidos: 120,
    utilizados: 0,
    pedidos_pagos: 60,
    valor_vendido: 3240,
    valor_online: 3000,
    valor_dinheiro: 240,
    taxa_plataforma: 240,
    ...over
  }
}

const linha = {
  organizacao: {
    organizacao_id: 'org-1',
    nome: 'Casa do Samba',
    slug: 'casa-do-samba',
    ativo: true,
    aprovada: true,
    lista_vip_ativa: false,
    taxa_servico: '2.00',
    criado_em: '2026-10-15T12:00:00Z',
    mercado_pago: { conectado: true, conectado_em: '2026-10-16T10:00:00Z', producao: true }
  },
  dono: {
    usuario_id: 'u-1',
    nome: 'José',
    email: 'jose@email.com',
    ativo: true,
    cadastrado_em: '2026-10-15T11:50:00Z',
    ultimo_acesso_em: null,
    email_confirmado: true,
    termos_versao: '2026-10',
    termos_aceitos_em: '2026-10-15T12:00:00Z',
    outras_casas: 0
  },
  equipe: [
    { usuario_id: 'u-1', nome: 'José', email: 'jose@email.com', perfil: 'ADMINISTRADOR', ativo: true, dono: true, ultimo_acesso_em: null },
    { usuario_id: 'u-2', nome: 'Rafa', email: 'rafa@email.com', perfil: 'PORTARIA', ativo: true, dono: false, ultimo_acesso_em: null }
  ],
  metricas: {
    eventos_total: 3,
    eventos_publicados: 2,
    eventos_ativos: 1,
    eventos_rascunho: 1,
    ingressos_vendidos: 200,
    ingressos_utilizados: 150,
    valor_vendido: 5400,
    valor_online: 5000,
    taxa_plataforma: 400,
    valor_reembolsado: '25.00'
  },
  eventos: [
    evento(),
    evento({ evento_id: 'ev-2', status: 'REALIZADO', utilizados: 75, vendidos: 80 }),
    evento({ evento_id: 'ev-3', publicacao_status: 'RASCUNHO', vendidos: 0 })
  ]
}

test('mapearDetalheCasa adapta o retorno do banco', () => {
  const d = mapearDetalheCasa(linha)
  assert.equal(d.organizacao.nome, 'Casa do Samba')
  assert.equal(d.organizacao.taxaServico, 2)
  assert.deepEqual(d.organizacao.mercadoPago, { conectadoEm: '2026-10-16T10:00:00Z', producao: true })
  assert.equal(d.dono?.email, 'jose@email.com')
  assert.equal(d.dono?.ultimoAcessoEm, null)
  assert.equal(d.equipe[1]?.perfil, 'PORTARIA')
  assert.equal(d.equipe[0]?.dono, true)
  assert.equal(d.metricas.eventosAtivos, 1)
  assert.equal(d.metricas.valorReembolsado, 25)
  assert.equal(d.metricas.valorDinheiro, 0)
  assert.equal(d.eventos.length, 3)
  assert.equal(d.eventos[0]?.valorVendido, 3240)
})

test('mapearDetalheCasa aceita casa sem dono, sem Mercado Pago e sem eventos', () => {
  const d = mapearDetalheCasa({ organizacao: { organizacao_id: 'x', nome: 'X' }, dono: null, equipe: null, metricas: null, eventos: null })
  assert.equal(d.dono, null)
  assert.equal(d.organizacao.mercadoPago, null)
  assert.deepEqual(d.equipe, [])
  assert.deepEqual(d.eventos, [])
  assert.equal(d.metricas.valorVendido, 0)
})

test('percentual, ticket medio e repasse online', () => {
  assert.equal(percentual(150, 200), 75)
  assert.equal(percentual(1, 3), 33)
  assert.equal(percentual(0, 0), null)
  assert.equal(ticketMedio(5400, 200), 27)
  assert.equal(ticketMedio(10, 3), 3.33)
  assert.equal(ticketMedio(100, 0), 0)
  assert.equal(repasseOnline({ valorOnline: 5000, taxaPlataforma: 400 }), 4600)
})

test('filtrarEventosCasa separa ativos, realizados e rascunhos', () => {
  const { eventos } = mapearDetalheCasa(linha)
  assert.deepEqual(filtrarEventosCasa(eventos, 'TODOS').map((e) => e.id), ['ev-1', 'ev-2', 'ev-3'])
  assert.deepEqual(filtrarEventosCasa(eventos, 'ATIVOS').map((e) => e.id), ['ev-1'])
  assert.deepEqual(filtrarEventosCasa(eventos, 'REALIZADOS').map((e) => e.id), ['ev-2'])
  assert.deepEqual(filtrarEventosCasa(eventos, 'RASCUNHOS').map((e) => e.id), ['ev-3'])
  assert.equal(eventoAtivo({ publicacaoStatus: 'PUBLICADO', status: 'EM_ANDAMENTO' }), true)
  assert.equal(eventoAtivo({ publicacaoStatus: 'RASCUNHO', status: 'AGENDADO' }), false)
})

test('detalhe da casa fica so para o super admin e sai da lista de organizacoes', () => {
  const lista = readFileSync(new URL('../app/pages/plataforma/organizacoes/index.vue', import.meta.url), 'utf8')
  assert.match(lista, /\/plataforma\/organizacoes\/\$\{casa\.id\}/)
  assert.match(lista, /Ver detalhes/)
  const pagina = readFileSync(new URL('../app/pages/plataforma/organizacoes/[id].vue', import.meta.url), 'utf8')
  assert.match(pagina, /ehSuperAdmin/)
  assert.match(pagina, /obterOrganizacaoPlataforma/)
  const migracao = readFileSync(
    new URL('../supabase/migrations/20261021020000_organizacao_detalhe_plataforma.sql', import.meta.url),
    'utf8'
  )
  assert.match(migracao, /usuario_e_super_admin\(\)/)
  assert.match(migracao, /revoke all on function public\.obter_organizacao_plataforma\(uuid\) from public, anon/)
  assert.doesNotMatch(migracao, /access_token|refresh_token/)
})
