import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

import {
  CHAVE_INGRESSOS_SALVOS,
  LIMITE_INGRESSOS_SALVOS,
  eventoJaPassou,
  lerPedidosSalvos,
  ordenarPedidosSalvos,
  removerPedidoSalvo,
  salvarPedido,
  type ArmazenamentoLike
} from '../app/utils/ingressosSalvos.ts'

function memoria(inicial: Record<string, string> = {}): ArmazenamentoLike & { dados: Record<string, string> } {
  const dados = { ...inicial }
  return {
    dados,
    getItem: (k) => (k in dados ? dados[k] : null),
    setItem: (k, v) => {
      dados[k] = v
    }
  }
}

const TOKEN = '11111111-2222-4333-8444-555555555555'
const base = {
  pedidoId: 'p1',
  checkoutToken: TOKEN,
  codigoPedido: 'IU100731',
  organizacaoSlug: 'casa-x',
  eventoSlug: 'pagode-sexta',
  eventoNome: 'Pagode de Sexta'
}

test('salva o pedido e le de volta', () => {
  const m = memoria()
  salvarPedido({ ...base, quantidade: 2 }, m, new Date('2026-10-19T12:00:00Z'))
  const lidos = lerPedidosSalvos(m)
  assert.equal(lidos.length, 1)
  assert.equal(lidos[0].checkoutToken, TOKEN)
  assert.equal(lidos[0].quantidade, 2)
  assert.equal(lidos[0].salvoEm, '2026-10-19T12:00:00.000Z')
})

test('atualizar o mesmo pedido nao duplica nem apaga dados ja salvos', () => {
  const m = memoria()
  salvarPedido({ ...base, quantidade: 2 }, m)
  salvarPedido({ ...base, eventoInicioEm: '2026-10-24T23:00:00Z', eventoLocal: 'Casa X' }, m)
  const lidos = lerPedidosSalvos(m)
  assert.equal(lidos.length, 1)
  assert.equal(lidos[0].quantidade, 2)
  assert.equal(lidos[0].eventoInicioEm, '2026-10-24T23:00:00Z')
})

test('ignora token invalido, dados corrompidos e respeita o limite', () => {
  const m = memoria({ [CHAVE_INGRESSOS_SALVOS]: '{nao e json' })
  assert.deepEqual(lerPedidosSalvos(m), [])
  salvarPedido({ ...base, checkoutToken: 'abc' }, m)
  assert.equal(m.dados[CHAVE_INGRESSOS_SALVOS], '{nao e json')
  for (let i = 0; i < LIMITE_INGRESSOS_SALVOS + 5; i++) salvarPedido({ ...base, pedidoId: `p${i}` }, m)
  const lidos = lerPedidosSalvos(m)
  assert.equal(lidos.length, LIMITE_INGRESSOS_SALVOS)
  assert.equal(lidos[0].pedidoId, `p${LIMITE_INGRESSOS_SALVOS + 4}`)
  assert.deepEqual(lerPedidosSalvos(null), [])
})

test('remover tira so o pedido escolhido', () => {
  const m = memoria()
  salvarPedido(base, m)
  salvarPedido({ ...base, pedidoId: 'p2' }, m)
  removerPedidoSalvo('p1', m)
  assert.deepEqual(lerPedidosSalvos(m).map((p) => p.pedidoId), ['p2'])
})

test('ordena proximos primeiro e passados por ultimo', () => {
  const agora = new Date('2026-10-19T12:00:00Z')
  const m = memoria()
  salvarPedido({ ...base, pedidoId: 'longe', eventoInicioEm: '2026-11-30T23:00:00Z' }, m)
  salvarPedido({ ...base, pedidoId: 'passado', eventoInicioEm: '2026-10-01T23:00:00Z' }, m)
  salvarPedido({ ...base, pedidoId: 'perto', eventoInicioEm: '2026-10-24T23:00:00Z' }, m)
  const ordem = ordenarPedidosSalvos(lerPedidosSalvos(m), agora)
  assert.deepEqual(ordem.map((p) => p.pedidoId), ['perto', 'longe', 'passado'])
  assert.equal(eventoJaPassou(ordem[2], agora), true)
  assert.equal(eventoJaPassou(ordem[0], agora), false)
})

test('paginas salvam e "Meus ingressos" lista os pedidos do aparelho', () => {
  const ler = (c: string) => readFileSync(new URL(c, import.meta.url), 'utf8')
  const pagamento = ler('../app/components/public/pagamento/PublicPaymentPage.vue')
  assert.match(pagamento, /salvarPedido\(/)
  assert.match(pagamento, /removerPedidoSalvo\(/)
  const ingressos = ler('../app/components/public/ingressos/PublicTicketsPage.vue')
  assert.match(ingressos, /salvarPedido\(/)
  const recuperacao = ler('../app/components/public/recuperacao/PublicRecoveryPage.vue')
  assert.match(recuperacao, /useIngressosSalvos/)
  assert.match(recuperacao, /Salvos neste aparelho/)
  assert.match(recuperacao, /rotaIngressosPedido\(/)
})
