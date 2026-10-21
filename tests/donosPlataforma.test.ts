import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import { filtrarCasasComDono, gerarCsvDonos, mapearCasaComDono } from '../app/utils/donosPlataforma.ts'

function linha(over: Record<string, unknown> = {}) {
  return {
    organizacao_id: 'org-1',
    organizacao_nome: 'Casa do Samba',
    organizacao_slug: 'casa-do-samba',
    ativo: true,
    aprovada: true,
    criado_em: '2026-10-15T12:00:00Z',
    dono: {
      usuario_id: 'u-1',
      nome: 'José Araújo',
      email: 'jose@email.com',
      ativo: true,
      cadastrado_em: '2026-10-15T11:50:00Z',
      ultimo_acesso_em: '2026-10-20T22:10:00Z',
      email_confirmado: true,
      termos_versao: '2026-10',
      termos_aceitos_em: '2026-10-15T12:00:00Z',
      outras_casas: 0
    },
    outros_administradores: [{ nome: 'Maria', email: 'maria@email.com' }],
    equipe: 3,
    eventos: 2,
    ingressos_vendidos: 140,
    mercado_pago_conectado: true,
    mercado_pago_conectado_em: '2026-10-16T10:00:00Z',
    ...over
  }
}

test('mapearCasaComDono adapta a linha do banco', () => {
  const c = mapearCasaComDono(linha())
  assert.equal(c.organizacaoNome, 'Casa do Samba')
  assert.equal(c.dono?.email, 'jose@email.com')
  assert.equal(c.dono?.emailConfirmado, true)
  assert.equal(c.dono?.termosVersao, '2026-10')
  assert.deepEqual(c.outrosAdministradores, [{ nome: 'Maria', email: 'maria@email.com' }])
  assert.equal(c.ingressosVendidos, 140)
  assert.equal(c.mercadoPagoConectado, true)
})

test('mapearCasaComDono aceita casa sem dono e campos vazios', () => {
  const c = mapearCasaComDono(linha({ dono: null, outros_administradores: null, eventos: null }))
  assert.equal(c.dono, null)
  assert.deepEqual(c.outrosAdministradores, [])
  assert.equal(c.eventos, 0)
})

test('filtrarCasasComDono busca sem acento por casa, nome e e-mail do dono', () => {
  const casas = [
    mapearCasaComDono(linha()),
    mapearCasaComDono(linha({ organizacao_id: 'org-2', organizacao_nome: 'Bar Novo', organizacao_slug: 'bar-novo', aprovada: false, mercado_pago_conectado: false, dono: { ...linha().dono, nome: 'Ana', email: 'ana@bar.com' } }))
  ]
  assert.equal(filtrarCasasComDono(casas, 'jose araujo', 'TODAS').length, 1)
  assert.equal(filtrarCasasComDono(casas, 'ANA@BAR', 'TODAS')[0]?.organizacaoId, 'org-2')
  assert.equal(filtrarCasasComDono(casas, 'samba', 'TODAS')[0]?.organizacaoId, 'org-1')
  assert.deepEqual(filtrarCasasComDono(casas, '', 'AGUARDANDO').map((c) => c.organizacaoId), ['org-2'])
  assert.deepEqual(filtrarCasasComDono(casas, '', 'APROVADAS').map((c) => c.organizacaoId), ['org-1'])
  assert.deepEqual(filtrarCasasComDono(casas, '', 'SEM_MERCADO_PAGO').map((c) => c.organizacaoId), ['org-2'])
})

test('gerarCsvDonos usa ponto e virgula, escapa aspas e neutraliza formulas', () => {
  const csv = gerarCsvDonos([
    mapearCasaComDono(linha({ organizacao_nome: 'Casa "Top"; Bar' })),
    mapearCasaComDono(linha({ organizacao_nome: '=HYPERLINK("x")', dono: null }))
  ])
  const linhas = csv.split('\r\n')
  assert.equal(linhas.length, 3)
  assert.match(linhas[0] ?? '', /^Casa;Endereco da casa;Situacao;/)
  assert.match(linhas[1] ?? '', /^"Casa ""Top""; Bar";casa-do-samba;Aprovada;15\/10\/2026;José Araújo;jose@email.com;Sim;/)
  assert.match(linhas[1] ?? '', /;maria@email.com;3;2;140;Conectado$/)
  assert.match(linhas[2] ?? '', /^"'=HYPERLINK\(""x""\)";/)
})

test('tela Donos das casas fica so para o super admin', () => {
  const sidebar = readFileSync(new URL('../app/components/AdminSidebar.vue', import.meta.url), 'utf8')
  assert.match(sidebar, /'\/plataforma\/donos'/)
  assert.match(sidebar, /label: 'Donos das casas'/)
  const pagina = readFileSync(new URL('../app/pages/plataforma/donos.vue', import.meta.url), 'utf8')
  assert.match(pagina, /sidebarActive: 'Donos das casas'/)
  assert.match(pagina, /ehSuperAdmin/)
  assert.match(pagina, /listarDonosPlataforma/)
  const migracao = readFileSync(
    new URL('../supabase/migrations/20261021010000_donos_plataforma.sql', import.meta.url),
    'utf8'
  )
  assert.match(migracao, /usuario_e_super_admin\(\)/)
  assert.match(migracao, /revoke all on function public\.listar_donos_plataforma\(\) from public, anon/)
  assert.doesNotMatch(migracao, /access_token|refresh_token/)
})
