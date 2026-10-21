import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  ETAPAS_CRM,
  conversaoEntreEtapas,
  csvProdutores,
  dadosParaBanco,
  etapaComprovada,
  filtrarProdutores,
  formDoProdutor,
  linkInstagram,
  linkWhatsapp,
  mapearIndicadoresCrm,
  mapearProdutorCrm,
  ordemEtapa,
  resumoIndicadores,
  situacaoAcao,
  sugestaoAvanco,
  validarFormCrm
} from '../app/utils/crm.ts'

function linha(over: Record<string, unknown> = {}) {
  return {
    id: 'p-1',
    nome_produtor: 'Produtor A',
    empresa_evento: 'Festa X',
    instagram: '@festax',
    whatsapp: '(34) 99999-0000',
    cidade: 'Uberlândia',
    tipo_evento: 'Festa universitária',
    ultimo_contato: '2026-10-21',
    etapa: 'CONTATADO',
    proxima_acao: 'Agendar demonstração',
    proxima_acao_em: '2026-10-23',
    observacoes: null,
    organizacao_id: null,
    organizacao_nome: null,
    eventos_publicados: 0,
    ingressos_vendidos: 0,
    receita_gerada: 0,
    ...over
  }
}

test('nove etapas na ordem do plano comercial', () => {
  assert.equal(ETAPAS_CRM.length, 9)
  assert.equal(ordemEtapa('MAPEADO'), 1)
  assert.equal(ordemEtapa('DEMO_REALIZADA'), 5)
  assert.equal(ordemEtapa('CLIENTE_RECORRENTE'), 9)
  assert.equal(ordemEtapa('X'), 0)
})

test('mapearProdutorCrm adapta o banco e troca null por texto vazio', () => {
  const p = mapearProdutorCrm(linha({ receita_gerada: '24.00', etapa: 'INVALIDA' }))
  assert.equal(p.nomeProdutor, 'Produtor A')
  assert.equal(p.observacoes, '')
  assert.equal(p.organizacaoId, '')
  assert.equal(p.receitaGerada, 24)
  assert.equal(p.etapa, 'MAPEADO')
})

test('formulario: validacao e payload em snake_case', () => {
  const f = formDoProdutor(mapearProdutorCrm(linha()))
  assert.equal(validarFormCrm(f), '')
  assert.equal(validarFormCrm({ ...f, nomeProdutor: '  ' }), 'Informe o nome do produtor.')
  assert.match(validarFormCrm({ ...f, proximaAcaoEm: '23/10/2026' }), /próxima ação/)
  const d = dadosParaBanco({ ...f, cidade: '  Uberlândia ' })
  assert.equal(d.cidade, 'Uberlândia')
  assert.equal(d.proxima_acao_em, '2026-10-23')
  assert.equal(d.organizacao_id, '')
})

test('links de WhatsApp e Instagram', () => {
  assert.equal(linkWhatsapp('(34) 99999-0000'), 'https://wa.me/5534999990000')
  assert.equal(linkWhatsapp('+55 34 99999-0000'), 'https://wa.me/5534999990000')
  assert.equal(linkWhatsapp(''), '')
  assert.equal(linkInstagram('@festax'), 'https://instagram.com/festax')
  assert.equal(linkInstagram('instagram.com/festax/'), 'https://instagram.com/festax')
  assert.equal(linkInstagram('https://instagram.com/festax'), 'https://instagram.com/festax')
})

test('situacao da proxima acao e filtro de acoes', () => {
  assert.equal(situacaoAcao('2026-10-20', '2026-10-21'), 'ATRASADA')
  assert.equal(situacaoAcao('2026-10-21', '2026-10-21'), 'HOJE')
  assert.equal(situacaoAcao('2026-10-23', '2026-10-21'), 'FUTURA')
  assert.equal(situacaoAcao('', '2026-10-21'), 'SEM_DATA')
  const lista = [
    mapearProdutorCrm(linha({ id: 'a', proxima_acao_em: '2026-10-20' })),
    mapearProdutorCrm(linha({ id: 'b', proxima_acao_em: '2026-10-30', etapa: 'INTERESSADO', cidade: 'Araguari' })),
    mapearProdutorCrm(linha({ id: 'c', proxima_acao_em: null }))
  ]
  assert.deepEqual(filtrarProdutores(lista, 'ACOES', '', '2026-10-21').map((p) => p.id), ['a'])
  assert.deepEqual(filtrarProdutores(lista, 'INTERESSADO', '', '2026-10-21').map((p) => p.id), ['b'])
  assert.deepEqual(filtrarProdutores(lista, 'TODOS', 'uberlandia', '2026-10-21').map((p) => p.id), ['a', 'c'])
})

test('etapa comprovada pelos numeros da casa e sugestao de avanco', () => {
  const base = mapearProdutorCrm(linha({ etapa: 'DEMO_REALIZADA' }))
  assert.equal(etapaComprovada(base), null)
  const casa = { ...base, organizacaoId: 'org-1' }
  assert.equal(etapaComprovada(casa), 'CADASTRO_INICIADO')
  assert.equal(etapaComprovada({ ...casa, eventosPublicados: 1 }), 'EVENTO_PUBLICADO')
  assert.equal(etapaComprovada({ ...casa, eventosPublicados: 1, ingressosVendidos: 3 }), 'PRIMEIRA_VENDA')
  assert.equal(etapaComprovada({ ...casa, eventosPublicados: 2, ingressosVendidos: 3 }), 'CLIENTE_RECORRENTE')
  assert.equal(sugestaoAvanco({ ...casa, eventosPublicados: 1 }), 'EVENTO_PUBLICADO')
  assert.equal(sugestaoAvanco({ ...casa, etapa: 'PRIMEIRA_VENDA', eventosPublicados: 1 }), null)
})

test('os sete indicadores a partir do funil do periodo', () => {
  const ind = mapearIndicadoresCrm({
    funil: [
      { etapa: 'MAPEADO', atual: 5, alcancaram: 20 },
      { etapa: 'CONTATADO', atual: 4, alcancaram: 15 },
      { etapa: 'INTERESSADO', atual: 2, alcancaram: 6 },
      { etapa: 'DEMO_AGENDADA', atual: 1, alcancaram: 5 },
      { etapa: 'DEMO_REALIZADA', atual: 1, alcancaram: 4 },
      { etapa: 'CADASTRO_INICIADO', atual: 1, alcancaram: 3 },
      { etapa: 'EVENTO_PUBLICADO', atual: 0, alcancaram: 1 }
    ],
    negocio: { eventos_publicados: 2, ingressos_vendidos: 120, valor_vendido: '3240.00', receita_liquida: '240.00' },
    acoes: { atrasadas: 1, hoje: 2, total_produtores: 15 }
  })
  assert.equal(ind.funil.length, 9)
  assert.equal(ind.funil[8]?.alcancaram, 0)
  const r = resumoIndicadores(ind)
  assert.equal(r.contatados, 15)
  assert.equal(r.taxaResposta, 40)
  assert.equal(r.demonstracoes, 4)
  assert.equal(r.conversaoAtivos, 25)
  assert.equal(r.ingressosVendidos, 120)
  assert.equal(r.receitaLiquida, 240)
  const c = conversaoEntreEtapas(ind)
  assert.equal(c.length, 8)
  assert.equal(c[0]?.percentual, 75)
  assert.equal(c[7]?.percentual, null)
  assert.equal(resumoIndicadores(mapearIndicadoresCrm({})).taxaResposta, null)
})

test('planilha CSV com as colunas do plano', () => {
  const csv = csvProdutores([mapearProdutorCrm(linha({ observacoes: 'Ligar; depois "manhã"', receita_gerada: 24 }))])
  const [cab, l1] = csv.replace('﻿', '').split('\r\n')
  assert.match(cab!, /^Nome do produtor;Empresa ou evento;Instagram;WhatsApp;Cidade;Tipo de evento;Último contato;Etapa comercial;Próxima ação;Data da próxima ação;Eventos publicados;Ingressos vendidos;Receita gerada/)
  assert.match(l1!, /21\/10\/2026;Contatado;Agendar demonstração;23\/10\/2026;0;0;24,00/)
  assert.match(l1!, /"Ligar; depois ""manhã"""$/)
})

test('CRM so para o super admin', () => {
  const pagina = readFileSync(new URL('../app/pages/plataforma/crm.vue', import.meta.url), 'utf8')
  assert.match(pagina, /ehSuperAdmin/)
  const sidebar = readFileSync(new URL('../app/components/AdminSidebar.vue', import.meta.url), 'utf8')
  const bloco = sidebar.slice(sidebar.indexOf('if (operador.value?.superAdmin)'))
  assert.ok(bloco.indexOf("'/plataforma/crm'") > 0)
  const migracao = readFileSync(new URL('../supabase/migrations/20261021030000_crm_comercial.sql', import.meta.url), 'utf8')
  assert.match(migracao, /revoke all on table public\.crm_produtores from public, anon, authenticated/)
  assert.match(migracao, /usuario_e_super_admin\(\)/)
  for (const fn of ['crm_listar_produtores', 'crm_salvar_produtor', 'crm_excluir_produtor', 'crm_importar_casas', 'crm_indicadores']) {
    assert.match(migracao, new RegExp(`create or replace function private\\.${fn}[\\s\\S]*?crm_exigir_super_admin\\(\\)`))
  }
})
