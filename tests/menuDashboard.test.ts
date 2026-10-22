import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const ler = (caminho: string) => readFileSync(new URL(caminho, import.meta.url), 'utf8')

test('menu lateral nao tem itens sem destino', () => {
  const sidebar = ler('../app/components/AdminSidebar.vue')
  assert.ok(!sidebar.includes("to: '#'"))
})

test('cabecalho do dashboard nao tem data fixa nem botoes sem acao', () => {
  const layout = ler('../app/layouts/DashboardTestLayout.vue')
  assert.ok(!layout.includes('29 de Agosto'))
  assert.ok(!layout.includes('<button'))
  assert.ok(layout.includes('route.meta.description'))
  assert.ok(!ler('../app/pages/painel.vue').includes('evento de hoje'))
})

test('atalhos do dashboard levam as telas certas', () => {
  const pedidos = ler('../app/components/RecentOrders.vue')
  assert.ok(pedidos.includes(':to="`/pedidos/${order.pedidoId}`"'))
  assert.ok(pedidos.includes('to="/pedidos"'))
  assert.ok(ler('../app/components/RecentEntries.vue').includes('to="/entradas"'))
  assert.ok(!ler('../app/components/EntriesByHourChart.vue').includes('<button'))
})
