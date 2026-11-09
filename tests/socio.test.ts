import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { decidirAcessoOperador, perfilOperaPortaria, perfilPermitido } from '../app/utils/auth.ts'
import { destinoAposConvite } from '../app/utils/convite.ts'
import { destinoAoAbrirApp } from '../app/utils/instalarApp.ts'
import {
  PERFIS_SOCIO,
  destinoInicialPerfil,
  podeVerItemSidebar,
  redirectPermitidoPerfil
} from '../app/utils/navegacao.ts'
import {
  mapearEventosSocio,
  mapearVendasEventoSocio,
  mensagemErroSocio,
  percentualVendido,
  rotuloDia
} from '../app/utils/socio.ts'
import {
  PERFIS_USUARIO,
  formularioValido,
  mapearUsuariosAdmin,
  rotuloPerfil,
  validarConvite,
  validarEdicao
} from '../app/utils/usuarios.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('perfil SOCIO entra no sistema, mas nao opera a portaria', () => {
  assert.equal(perfilPermitido('SOCIO'), true)
  assert.equal(perfilOperaPortaria('SOCIO'), false)
  assert.equal(decidirAcessoOperador({ temSessao: true, perfil: 'SOCIO', ativo: true }), 'NEGAR')
  assert.equal(decidirAcessoOperador({ temSessao: true, perfil: 'PORTARIA', ativo: true }), 'PERMITIR')
})

test('tela inicial por perfil', () => {
  assert.equal(destinoInicialPerfil('SOCIO'), '/socio')
  assert.equal(destinoInicialPerfil('PORTARIA'), '/portaria')
  assert.equal(destinoInicialPerfil('ADMINISTRADOR'), '/painel')
  assert.equal(destinoAposConvite('SOCIO'), '/socio')
  assert.equal(destinoAoAbrirApp({ perfil: 'SOCIO', ativo: true, temIngressosSalvos: false }), '/socio')
})

test('redirect pos-login respeita a area de cada perfil', () => {
  assert.equal(redirectPermitidoPerfil('/socio/abc', 'SOCIO'), true)
  assert.equal(redirectPermitidoPerfil('/pedidos', 'SOCIO'), false)
  assert.equal(redirectPermitidoPerfil('/portaria', 'SOCIO'), false)
  assert.equal(redirectPermitidoPerfil('/socionovo', 'SOCIO'), false)
  assert.equal(redirectPermitidoPerfil('/portaria', 'PORTARIA'), true)
  assert.equal(redirectPermitidoPerfil('/socio', 'PORTARIA'), false)
  assert.equal(redirectPermitidoPerfil('/financeiro', 'ADMINISTRADOR'), true)
})

test('menu: socio ve so Vendas', () => {
  const sidebar = ler('../app/components/AdminSidebar.vue')
  assert.ok(sidebar.includes("{ to: '/socio', icon: ChartBarIcon, label: 'Vendas', allowedProfiles: PERFIS_SOCIO }"))
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_SOCIO }, 'SOCIO'), true)
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_SOCIO }, 'ADMINISTRADOR'), false)
  assert.equal(podeVerItemSidebar({ allowedProfiles: ['ADMINISTRADOR'] }, 'SOCIO'), false)
  assert.equal(podeVerItemSidebar({ allowedProfiles: ['ADMINISTRADOR', 'PORTARIA'] }, 'SOCIO'), false)
})

test('paginas do socio usam o middleware socio-auth', () => {
  assert.ok(ler('../app/pages/socio/index.vue').includes("middleware: ['socio-auth']"))
  assert.ok(ler('../app/pages/socio/[id].vue').includes("middleware: ['socio-auth']"))
  assert.ok(ler('../app/middleware/admin-auth.ts').includes("navigateTo('/socio')"))
  assert.ok(ler('../app/middleware/operator-auth.ts').includes("navigateTo('/socio')"))
})

test('perfil Socio do Evento nos usuarios', () => {
  assert.ok(PERFIS_USUARIO.includes('SOCIO'))
  assert.equal(rotuloPerfil('SOCIO'), 'Sócio do Evento')
  assert.ok(!formularioValido(validarConvite({ nome: 'S', email: 's@x.com', perfil: 'SOCIO' })))
  assert.ok(!formularioValido(validarConvite({ nome: 'S', email: 's@x.com', perfil: 'SOCIO', eventoIds: [] })))
  assert.ok(formularioValido(validarConvite({ nome: 'S', email: 's@x.com', perfil: 'SOCIO', eventoIds: ['e1'] })))
  assert.ok(formularioValido(validarConvite({ nome: 'P', email: 'p@x.com', perfil: 'PORTARIA' })))
  assert.ok(!formularioValido(validarEdicao({ id: 'a', nome: 'S', perfil: 'SOCIO', ativo: true, eventoIds: [] })))

  const [socio, portaria] = mapearUsuariosAdmin([
    { id: '1', nome: 'S', email: 's@x', perfil: 'SOCIO', ativo: true, ultimo_acesso_em: null, criado_em: '2026-11-01T00:00:00Z', eventos_socio: [{ id: 'e1', nome: 'Pagode' }] },
    { id: '2', nome: 'P', email: 'p@x', perfil: 'PORTARIA', ativo: true, ultimo_acesso_em: null, criado_em: '2026-11-01T00:00:00Z', eventos_socio: [{ id: 'e1', nome: 'Pagode' }] }
  ])
  assert.deepEqual(socio.eventosSocio, [{ id: 'e1', nome: 'Pagode' }])
  assert.deepEqual(portaria.eventosSocio, [])
})

test('convite aceita SOCIO e exige eventos da casa', () => {
  const endpoint = ler('../server/api/admin/users/invite.post.ts')
  assert.ok(endpoint.includes("const PERFIS = ['ADMINISTRADOR', 'PORTARIA', 'SOCIO']"))
  assert.ok(endpoint.includes(".eq('organizacao_id', organizacaoId)"))
  assert.ok(endpoint.includes("from('socios_eventos')"))
})

test('mapeia a lista e o detalhe de vendas do socio', () => {
  const lista = mapearEventosSocio([
    {
      evento_id: 'e1',
      nome: 'Pagode',
      imagem_url: 'javascript:alert(1)',
      inicio_em: '2026-11-20T23:00:00Z',
      local: 'Casa',
      status: 'AGENDADO',
      vendas_status: 'ABERTAS',
      resumo: { vendidos: 50, capacidade: 200, bruto: '1500.00', liquido: 1450, taxa: 50 }
    }
  ])
  assert.equal(lista.length, 1)
  assert.equal(lista[0].imagemUrl, null)
  assert.equal(lista[0].vendasAbertas, true)
  assert.equal(lista[0].resumo.bruto, 1500)
  assert.equal(percentualVendido(lista[0].resumo), 25)
  assert.equal(percentualVendido({ vendidos: 5, capacidade: 0 }), 0)

  const v = mapearVendasEventoSocio({
    evento: { evento_id: 'e1', nome: 'Pagode', vendas_status: 'ENCERRADAS' },
    resumo: { vendidos: 3, liquido: 90 },
    porForma: [{ forma: 'PIX', pedidos: 1, ingressos: 1, valor: 33 }, { forma: 'X', valor: 1 }],
    porLote: [{ lote: 'Lote 1', setor: null, vendidos: 3, quantidade: 100, preco: 30, valor: 90 }],
    porDia: [{ dia: '2026-11-01', ingressos: 2, valor: 60 }],
    entradasPorHora: [{ hora: '23h', entradas: 1 }]
  })
  assert.equal(v.evento.resumo.liquido, 90)
  assert.equal(v.evento.vendasAbertas, false)
  assert.equal(v.porForma[0].rotulo, 'Pix')
  assert.equal(v.porForma[1].forma, 'OUTRO')
  assert.equal(v.porLote[0].setor, null)
  assert.equal(rotuloDia(v.porDia[0].dia), '01/11')
  assert.equal(v.entradasPorHora[0].entradas, 1)
})

test('mensagens de erro do socio', () => {
  assert.match(mensagemErroSocio({ code: '42501' }), /acesso de sócio/)
  assert.match(mensagemErroSocio({ code: '23503' }), /não está liberado/)
  assert.match(mensagemErroSocio(null), /Tente novamente/)
})
