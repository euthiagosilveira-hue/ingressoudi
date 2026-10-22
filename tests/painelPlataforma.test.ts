import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  inicioDoPeriodo,
  mapearPainelPlataforma,
  ocupacao,
  resumirNomes,
  situacaoEvento,
  variacao
} from '../app/utils/painelPlataforma.ts'

const ler = (caminho: string) => readFileSync(new URL(caminho, import.meta.url), 'utf8')

test('mapearPainelPlataforma converte numeros e listas da RPC', () => {
  const p = mapearPainelPlataforma({
    metricas: { ingressos: '12', valor: '480.50', taxa: '24', pedidos: 5, casas_ativas: 3, casas_novas: 1, eventos_vendas_abertas: 4, casas_vendas_abertas: 2, casas_em_analise: 1 },
    anterior: { ingressos: 10, valor: 400, taxa: 20, pedidos: 4 },
    eventos: [
      { evento_id: 'e1', nome: 'Show', imagem_url: null, inicio_em: '2026-10-22T23:00:00Z', local: 'Bar', status: 'AGENDADO', vendas_status: 'ABERTAS', capacidade_total: 100, vendidos: '40', utilizados: 0, organizacao_id: 'o1', organizacao_nome: 'Bar do Samba' }
    ],
    ranking: [{ organizacao_id: 'o1', nome: 'Bar do Samba', ingressos: 12, pedidos: 5, valor: '480.50', taxa: '24' }],
    alertas: {
      casas_sem_mercado_pago: [{ organizacao_id: 'o2', nome: 'Galpao' }],
      casas_sem_evento: [],
      eventos_sem_vendas: [],
      pix_recusados_24h: [{ organizacao_id: 'o1', nome: 'Bar do Samba', quantidade: 2 }]
    },
    atividade: [{ tipo: 'VENDA', em: '2026-10-22T12:00:00Z', organizacao_id: 'o1', organizacao_nome: 'Bar do Samba', evento_nome: 'Show', quantidade: 2, valor: '80' }]
  })
  assert.equal(p.metricas.valor, 480.5)
  assert.equal(p.metricas.casasAtivas, 3)
  assert.equal(p.anterior?.ingressos, 10)
  assert.equal(p.eventos[0]?.vendidos, 40)
  assert.equal(p.eventos[0]?.organizacaoNome, 'Bar do Samba')
  assert.equal(p.ranking[0]?.valor, 480.5)
  assert.equal(p.alertas.casasSemMercadoPago[0]?.nome, 'Galpao')
  assert.equal(p.alertas.pixRecusados[0]?.quantidade, 2)
  assert.equal(p.atividade[0]?.valor, 80)
})

test('mapearPainelPlataforma aguenta resposta vazia e periodo "Tudo"', () => {
  const p = mapearPainelPlataforma({ metricas: {}, anterior: null })
  assert.equal(p.anterior, null)
  assert.deepEqual(p.eventos, [])
  assert.equal(p.metricas.taxa, 0)
})

test('inicioDoPeriodo: hoje comeca a meia-noite de Sao Paulo', () => {
  const agora = new Date('2026-10-22T02:30:00Z') // 21/10 23h30 em Sao Paulo
  assert.equal(inicioDoPeriodo('HOJE', agora), '2026-10-21T03:00:00.000Z')
  assert.equal(inicioDoPeriodo('7_DIAS', agora), '2026-10-15T02:30:00.000Z')
  assert.equal(inicioDoPeriodo('TUDO', agora), null)
})

test('variacao compara com o periodo anterior', () => {
  assert.equal(variacao(118, 100), '+18% vs. período anterior')
  assert.equal(variacao(50, 100), '-50% vs. período anterior')
  assert.equal(variacao(10, 0), 'Novo no período')
  assert.equal(variacao(10, null), '')
})

test('situacaoEvento e ocupacao do cartao', () => {
  const agora = new Date('2026-10-22T12:00:00Z')
  const base = { status: 'AGENDADO' as const, vendasStatus: 'ABERTAS' as const, capacidade: 100 }
  assert.equal(situacaoEvento({ ...base, status: 'EM_ANDAMENTO', vendidos: 5, inicioEm: '2026-10-22T11:00:00Z' }, agora).rotulo, 'Em andamento')
  assert.equal(situacaoEvento({ ...base, vendidos: 5, inicioEm: '2026-10-23T23:00:00Z' }, agora).rotulo, 'Vendendo pouco')
  assert.equal(situacaoEvento({ ...base, vendidos: 5, inicioEm: '2026-11-10T23:00:00Z' }, agora).rotulo, 'Vendas abertas')
  assert.equal(situacaoEvento({ ...base, vendasStatus: 'ENCERRADAS', vendidos: 5, inicioEm: '2026-10-23T23:00:00Z' }, agora).rotulo, 'Vendas encerradas')
  assert.equal(ocupacao(150, 100), 100)
  assert.equal(ocupacao(5, 0), 0)
  assert.equal(resumirNomes(['A', 'B', 'C', 'D', 'E']), 'A, B, C e mais 2')
})

test('painel da plataforma: rota, menu e cartao abrindo o dashboard do evento', () => {
  const pagina = ler('../app/pages/plataforma/painel.vue')
  assert.ok(pagina.includes("sidebarActive: 'Painel da plataforma'"))
  assert.ok(pagina.includes('ehSuperAdmin'))
  assert.ok(pagina.includes('`/eventos/${e.id}/dashboard`'))
  const sidebar = ler('../app/components/AdminSidebar.vue')
  assert.ok(sidebar.includes("to: '/plataforma/painel'"))
  assert.ok(sidebar.includes("'Minha organização'"))
  assert.ok(ler('../app/pages/login.vue').includes("navigateTo('/plataforma/painel')"))
})

test('modo suporte: faixa de aviso, bloqueios e reembolso', () => {
  assert.ok(ler('../app/components/AdminShell.vue').includes('Modo suporte:'))
  for (const p of ['../app/pages/configuracoes/mercado-pago.vue', '../app/pages/configuracoes/usuarios.vue']) {
    assert.ok(ler(p).includes("'sem-modo-suporte'"), `${p} deveria bloquear o modo suporte`)
  }
  assert.ok(ler('../server/api/admin/pedidos/[id]/reembolso.post.ts').includes('permitirSuporte: true'))
  assert.ok(!ler('../server/api/mercadopago/oauth/iniciar.get.ts').includes('permitirSuporte'))
  const migracao = ler('../supabase/migrations/20261022010000_painel_plataforma_modo_suporte.sql')
  assert.match(migracao, /MODO_SUPORTE_INICIADO/)
  assert.match(migracao, /private\.desconectar_mercado_pago\(\)[\s\S]*?exigir_fora_do_modo_suporte\(\)/)
  assert.match(migracao, /private\.atualizar_usuario_admin\([\s\S]*?exigir_fora_do_modo_suporte\(\)/)
  assert.match(migracao, /revoke all on function public\.obter_painel_plataforma\(timestamptz\) from public, anon/)
})
