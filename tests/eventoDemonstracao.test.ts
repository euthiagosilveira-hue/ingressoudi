import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('modo demonstracao: acoes aparecem so para o super admin e pelo status', () => {
  const acoes = ler('../app/components/eventos/EventCardActions.vue')
  assert.ok(acoes.includes('superAdmin'))
  assert.ok(acoes.includes("props.status === 'AGENDADO'"))
  assert.ok(acoes.includes("props.status === 'EM_ANDAMENTO'"))
  assert.ok(acoes.includes("selecionar('iniciar-agora')"))
  assert.ok(acoes.includes("selecionar('reabrir-vendas')"))
})

test('modo demonstracao: pagina confirma antes e usa as RPCs seguras', () => {
  const pagina = ler('../app/pages/eventos/index.vue')
  assert.ok(pagina.includes('ConfirmDialog'))
  assert.ok(pagina.includes('iniciarEventoAgora'))
  assert.ok(pagina.includes('reabrirVendasDemonstracao'))
  const servico = ler('../app/services/admin/eventos.ts')
  assert.ok(servico.includes("rpc('iniciar_evento_agora'"))
  assert.ok(servico.includes("rpc('reabrir_vendas_demonstracao'"))
})
