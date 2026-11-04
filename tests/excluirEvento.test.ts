import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  itensExclusao,
  mapearResumoExclusao,
  mensagemErroExclusao,
  nomeConfere,
  temVendasPagas
} from '../app/utils/excluirEvento.ts'

const base = {
  evento_id: 'e1', nome: 'Demo São João', organizacao_nome: 'Casa Um',
  pedidos: 3, pedidos_pagos: 2, pedidos_pagos_online: 1, valor_pago: '24.50', pix_pendentes: 1,
  ingressos: 4, entradas: 1, lista_vip: 0, lotes: 1, setores: 1
}

test('mapeia o resumo vindo do banco', () => {
  const r = mapearResumoExclusao(base)
  assert.equal(r.valorPago, 24.5)
  assert.equal(r.pedidosPagos, 2)
  assert.equal(r.listaVip, 0)
  assert.equal(temVendasPagas(r), true)
  assert.equal(temVendasPagas(mapearResumoExclusao({ ...base, pedidos_pagos: 0 })), false)
})

test('lista só o que existe, no singular e no plural', () => {
  const itens = itensExclusao(mapearResumoExclusao(base))
  assert.deepEqual(itens, ['3 pedidos', '4 ingressos', '1 entrada registrada na portaria', '1 lote', '1 setor'])
})

test('nome confere sem diferenciar acento, maiúscula e espaços', () => {
  assert.equal(nomeConfere('  demo sao   joao ', 'Demo São João'), true)
  assert.equal(nomeConfere('Demo São', 'Demo São João'), false)
  assert.equal(nomeConfere('', ''), false)
})

test('mensagens de erro', () => {
  assert.match(mensagemErroExclusao('Permissao negada: apenas super administrador'), /super administrador/)
  assert.match(mensagemErroExclusao('EVENTO_COM_VENDAS_PAGAS: o evento tem 2'), /vendas pagas/)
  assert.match(mensagemErroExclusao('Evento nao encontrado'), /já foi excluído/)
  assert.equal(mensagemErroExclusao(null), 'Não foi possível excluir o evento.')
})

test('botão excluir fica na página de eventos da plataforma, que é só do super admin', () => {
  const pagina = readFileSync(new URL('../app/pages/plataforma/eventos.vue', import.meta.url), 'utf8')
  assert.match(pagina, /ExcluirEventoModal/)
  assert.match(pagina, /v-if="!ehSuperAdmin"/)
  const sql = readFileSync(new URL('../supabase/migrations/20261104010000_excluir_evento_plataforma.sql', import.meta.url), 'utf8')
  assert.equal((sql.match(/usuario_e_super_admin\(\)/g) ?? []).length, 2)
})
