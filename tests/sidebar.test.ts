import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  PERFIS_ADMIN,
  PERFIS_ADMIN_PORTARIA,
  podeVerItemSidebar,
  podeVerListaVip
} from '../app/utils/navegacao.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const sidebar = ler('../app/components/AdminSidebar.vue')
const shell = ler('../app/components/AdminShell.vue')

test('sidebar nao usa numeros hardcoded nem props de contador/badge', () => {
  assert.ok(!sidebar.includes("'128'"))
  assert.ok(!sidebar.includes("'281'"))
  assert.ok(!/\bbadge\b/.test(sidebar))
  assert.ok(!sidebar.includes('pedidosCount'))
  assert.ok(!sidebar.includes('entradasCount'))
})

test('card do usuario permanece', () => {
  assert.ok(sidebar.includes('operador.nome'))
  assert.ok(sidebar.includes('operador.email'))
  assert.ok(sidebar.includes('Sair'))
})

test('card de ajuda continua removido', () => {
  assert.ok(!sidebar.includes('Precisa de ajuda?'))
  assert.ok(!sidebar.includes('Fale com o suporte'))
  assert.ok(!sidebar.includes('PhoneIcon'))
})

test('layout desktop/mobile preservado e sem camada de contadores', () => {
  assert.ok(shell.includes('class="hidden lg:flex"'))
  assert.ok(/<AdminSidebar[\s\S]*mobile/.test(shell))
  assert.ok(!shell.includes('useAdminSidebarCounts'))
})

// A) ADMINISTRADOR ve o menu completo
test('ADMINISTRADOR ve o menu completo', () => {
  const itens = [
    { allowedProfiles: PERFIS_ADMIN }, // Dashboard, Eventos, Pedidos, ...
    { allowedProfiles: PERFIS_ADMIN_PORTARIA } // Portaria
  ]
  assert.ok(itens.every((item) => podeVerItemSidebar(item, 'ADMINISTRADOR')))
  assert.equal(podeVerListaVip('ADMINISTRADOR'), true)
})

// B/C/D/E) PORTARIA ve apenas Portaria
test('PORTARIA ve apenas Portaria', () => {
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_ADMIN_PORTARIA }, 'PORTARIA'), true)
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_ADMIN }, 'PORTARIA'), false)
})

test('PORTARIA nao ve Configuracoes, Lista VIP nem Dashboard', () => {
  const adminOnly = [
    { to: '/configuracoes', allowedProfiles: PERFIS_ADMIN },
    { to: '/lista-vip', allowedProfiles: PERFIS_ADMIN },
    { to: '/', allowedProfiles: PERFIS_ADMIN }
  ]
  assert.ok(adminOnly.every((item) => !podeVerItemSidebar(item, 'PORTARIA')))
  assert.equal(podeVerListaVip('PORTARIA'), false)
})

// Regra central unica
test('sidebar usa o helper central e allowedProfiles (sem adminOnly espalhado)', () => {
  assert.ok(sidebar.includes('podeVerItemSidebar'))
  assert.ok(sidebar.includes('allowedProfiles'))
  assert.ok(sidebar.includes('PERFIS_ADMIN_PORTARIA'))
  assert.ok(!sidebar.includes('adminOnly'))
})

// H) loading de perfil nao mostra menu indevido
test('sidebar so renderiza itens apos resolver o perfil', () => {
  assert.ok(sidebar.includes('perfilResolvido'))
  assert.ok(sidebar.includes('carregado'))
  assert.ok(sidebar.includes(': []'))
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_ADMIN }, null), false)
  assert.equal(podeVerItemSidebar({ allowedProfiles: PERFIS_ADMIN_PORTARIA }, null), false)
})

// F/G) mobile e item ativo
test('mobile compartilha a mesma lista filtrada', () => {
  assert.ok(/<AdminSidebar[\s\S]*mobile/.test(shell))
})

test('Portaria continua no sidebar e ativa em /portaria', () => {
  assert.ok(sidebar.includes("label: 'Portaria'"))
  assert.ok(sidebar.includes('PERFIS_ADMIN_PORTARIA'))
  const page = ler('../app/pages/portaria/index.vue')
  assert.ok(page.includes("sidebarActive: 'Portaria'"))
})

// I) rotas continuam protegidas pelos middlewares
test('rotas admin continuam protegidas por admin-auth', () => {
  const middleware = ler('../app/middleware/admin-auth.ts')
  assert.ok(middleware.includes("perfil.perfil !== 'ADMINISTRADOR'"))

  const paginas = [
    '../app/pages/index.vue',
    '../app/pages/lista-vip.vue',
    '../app/pages/configuracoes/usuarios.vue',
    '../app/pages/eventos/index.vue',
    '../app/pages/pedidos/index.vue',
    '../app/pages/ingressos/index.vue',
    '../app/pages/entradas/index.vue',
    '../app/pages/financeiro/index.vue'
  ]
  for (const pagina of paginas) {
    assert.ok(
      ler(pagina).includes("middleware: ['admin-auth']"),
      `${pagina} deveria exigir admin-auth`
    )
  }

  // /portaria usa operator-auth (ADMIN ou PORTARIA)
  assert.ok(ler('../app/pages/portaria/index.vue').includes("middleware: ['operator-auth']"))
})
