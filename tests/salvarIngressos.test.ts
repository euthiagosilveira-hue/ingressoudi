import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { emailPareceValido, linkWhatsappIngressos, normalizarEmail } from '../app/utils/publicIngressos.ts'
import { PUBLIC_NAV_ITEMS } from '../app/utils/publicNav.ts'

function ler(caminho: string): string {
  return readFileSync(fileURLToPath(new URL(caminho, import.meta.url)), 'utf8')
}

test('passo a passo do Pix acima do codigo e aviso depois de copiar', () => {
  const card = ler('../app/components/public/pagamento/PaymentPendingCard.vue')
  assert.ok(card.includes("'Copie o código.'"))
  assert.ok(card.includes("'Pague no app do banco.'"))
  assert.ok(card.includes("'Volte aqui, seu ingresso aparece nesta tela.'"))
  assert.ok(card.indexOf('PASSOS_PIX"') < card.indexOf('<QrcodeVue'))
  assert.ok(card.includes('Depois de pagar, volte para esta página!'))
  assert.ok(card.includes('v-if="jaCopiou"'))
})

test('ao voltar do banco confere o pagamento e abre o ingresso sozinho', () => {
  const pagamento = ler('../app/composables/usePublicPayment.ts')
  assert.ok(pagamento.includes("addEventListener('visibilitychange'"))
  assert.ok(pagamento.includes("addEventListener('pageshow'"))
  assert.ok(pagamento.includes("removeEventListener('visibilitychange'"))
  const pagina = ler('../app/components/public/pagamento/PublicPaymentPage.vue')
  assert.ok(/situacao !== 'PAGO'/.test(pagina))
  assert.ok(pagina.includes('navigateTo(rotaIngressosPedido('))
})

test('"Meus ingressos" aparece como botao no topo', () => {
  assert.ok(PUBLIC_NAV_ITEMS.find((i) => i.label === 'Meus ingressos')?.destaque)
  assert.ok(ler('../app/components/public/PublicHeader.vue').includes('item.destaque'))
})

test('busca por telefone + e-mail salva os pedidos no aparelho', () => {
  const pagina = ler('../app/components/public/recuperacao/PublicRecoveryPage.vue')
  assert.ok(pagina.includes('buscarIngressosPorContato'))
  assert.ok(pagina.includes('salvarPedido(p)'))
  assert.ok(pagina.includes('E-mail usado na compra'))
  assert.ok(ler('../app/services/public/recuperacao.ts').includes("rpc('buscar_ingressos_contato'"))
})

test('normalizarEmail e emailPareceValido', () => {
  assert.equal(normalizarEmail('  Ana@Mail.COM '), 'ana@mail.com')
  assert.ok(emailPareceValido(' ana@mail.com '))
  assert.ok(!emailPareceValido('ana@mail'))
  assert.ok(!emailPareceValido('ana mail.com'))
  assert.ok(!emailPareceValido(''))
})

test('link do WhatsApp leva a mensagem com o link dos ingressos', () => {
  const url = 'https://www.ingressoudi.com.br/casa/evento/comprar/ingressos?token=abc'
  const link = linkWhatsappIngressos({ url, eventoNome: 'Pagode & Cia' })
  assert.ok(link.startsWith('https://wa.me/?text='))
  const texto = decodeURIComponent(link.slice('https://wa.me/?text='.length))
  assert.equal(texto, `Meus ingressos para Pagode & Cia: ${url}`)
})

test('botao "Enviar para meu WhatsApp" so com o link permanente da compra', () => {
  const pagina = ler('../app/components/public/ingressos/PublicTicketsPage.vue')
  assert.ok(pagina.includes('Enviar para meu WhatsApp'))
  assert.ok(pagina.includes('v-if="linkWhatsapp"'))
  assert.ok(pagina.includes('!token.value'))
})
