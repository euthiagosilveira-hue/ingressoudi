import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { formatarDiaIso, periodoDoPreset, validarPeriodo } from '../app/utils/financeiroPlataforma.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

const hoje = new Date(2026, 9, 15) // 15/10/2026

test('presets de periodo', () => {
  assert.deepEqual(periodoDoPreset('HOJE', hoje), { inicio: '2026-10-15', fim: '2026-10-15' })
  assert.deepEqual(periodoDoPreset('7D', hoje), { inicio: '2026-10-09', fim: '2026-10-15' })
  assert.deepEqual(periodoDoPreset('30D', hoje), { inicio: '2026-09-16', fim: '2026-10-15' })
  assert.deepEqual(periodoDoPreset('MES', hoje), { inicio: '2026-10-01', fim: '2026-10-15' })
  assert.deepEqual(periodoDoPreset('MES_ANTERIOR', hoje), { inicio: '2026-09-01', fim: '2026-09-30' })
  assert.deepEqual(periodoDoPreset('MES_ANTERIOR', new Date(2026, 0, 10)), { inicio: '2025-12-01', fim: '2025-12-31' })
  assert.equal(periodoDoPreset('PERSONALIZADO', hoje), null)
})

test('validacao do periodo segue as regras do banco', () => {
  assert.equal(validarPeriodo({ inicio: '2026-10-01', fim: '2026-10-15' }), '')
  assert.match(validarPeriodo({ inicio: '2026-10-15', fim: '2026-10-01' }), /posterior/)
  assert.match(validarPeriodo({ inicio: '2025-01-01', fim: '2026-10-15' }), /1 ano/)
  assert.match(validarPeriodo({ inicio: '', fim: '2026-10-15' }), /duas datas/)
})

test('data exibida no formato brasileiro', () => {
  assert.equal(formatarDiaIso('2026-10-15'), '15/10/2026')
})

test('pagina e menu: somente super admin, via RPC segura', () => {
  const pagina = ler('../app/pages/plataforma/financeiro.vue')
  assert.ok(pagina.includes('superAdmin'))
  assert.ok(pagina.includes('obterFinanceiroPlataforma'))
  const servico = ler('../app/services/admin/financeiroPlataforma.ts')
  assert.ok(servico.includes("rpc('financeiro_plataforma'"))
  const sidebar = ler('../app/components/AdminSidebar.vue')
  assert.ok(sidebar.includes("to: '/plataforma/financeiro'"))
})
