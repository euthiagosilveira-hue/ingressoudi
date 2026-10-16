import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { criarReservaMock, mensagemErroReserva } from '../app/utils/checkout.ts'
import { mapearResultadoEntradaRpc } from '../app/utils/gate.ts'
import {
  contarMeias,
  precoMeia,
  rotuloTipoIngresso,
  valorIngressosComMeia
} from '../app/utils/meiaEntrada.ts'
import { calcularValoresCheckout } from '../app/utils/taxa.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('meia-entrada vale 50% do lote, arredondada em centavos como no banco', () => {
  assert.equal(precoMeia(50), 25)
  assert.equal(precoMeia(25), 12.5)
  assert.equal(precoMeia(1.25), 0.63)
  assert.equal(precoMeia(19.99), 10)
  assert.equal(precoMeia(0.05), 0.03)
  assert.equal(precoMeia(null), 0)
  assert.equal(precoMeia(0), 0)
})

test('valor dos ingressos soma inteiras e meias', () => {
  assert.equal(valorIngressosComMeia(50, 3, 2), 100)
  assert.equal(valorIngressosComMeia(50, 3, 0), 150)
  assert.equal(valorIngressosComMeia(50, 2, 5), 50)
  assert.equal(contarMeias([{ meia: true }, { meia: false }, {}, { meia: true }]), 2)
  assert.equal(rotuloTipoIngresso(true), 'Meia-entrada')
  assert.equal(rotuloTipoIngresso(false), 'Inteira')
})

test('a taxa de servico por ingresso nao muda com a meia-entrada', () => {
  assert.deepEqual(calcularValoresCheckout(50, 3, 1, 2), { valorIngressos: 100, valorTaxa: 3, total: 103 })
  assert.deepEqual(calcularValoresCheckout(50, 3, 1), { valorIngressos: 150, valorTaxa: 3, total: 153 })
})

test('reserva de demonstracao marca as meias', () => {
  const evento = { eventoId: 'e1', loteId: 'l1', preco: 50 } as Parameters<typeof criarReservaMock>[0]
  const reserva = criarReservaMock(evento, {
    quantidade: 2,
    participantes: [{ nome: 'Ana', meia: true }, { nome: 'Bia' }],
    comprador: { nome: 'C', telefone: '11999999999', email: 'c@c.com' }
  })
  assert.equal(reserva.valorTotal, 75)
  assert.equal(reserva.quantidadeMeia, 1)
  assert.deepEqual(reserva.ingressos.map((i) => i.meia), [true, false])
  assert.match(mensagemErroReserva('MEIA_INDISPONIVEL'), /meia-entrada/)
})

test('portaria recebe o aviso de meia-entrada', () => {
  assert.equal(mapearResultadoEntradaRpc({ resultado: 'LIBERADO', meia: true }).meia, true)
  assert.equal(mapearResultadoEntradaRpc({ resultado: 'LIBERADO' }).meia, false)
  assert.ok(ler('../app/components/portaria/GateQrScanner.vue').includes('conferir documento'))
  assert.ok(ler('../app/components/portaria/GateNameSearchPanel.vue').includes('conferir documento'))
})

test('checkout envia as meias ao banco e o painel liga a opcao no evento', () => {
  assert.ok(ler('../app/services/public/reservas.ts').includes('p_meias'))
  assert.ok(ler('../app/services/admin/eventos.ts').includes("rpc('definir_meia_entrada_evento_admin'"))
  assert.ok(ler('../app/pages/eventos/[id]/lotes.vue').includes('EventMeiaCard'))
  assert.ok(ler('../app/pages/eventos/[id]/editar.vue').includes('EventMeiaCard'))
  const migration = ler('../supabase/migrations/20261016060000_meia_entrada.sql')
  assert.ok(migration.includes('add column meia_entrada_ativa'))
  assert.ok(migration.includes('p_meias boolean[]'))
})
