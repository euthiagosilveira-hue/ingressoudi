// Ingressoudi - teste dos Pagamentos Avancados do Mercado Pago (split com data de liberacao).
// Responde, na pratica, se a conta da plataforma consegue:
//   1. criar um pagamento avancado com Pix e money_release_date no vendedor;
//   2. reter por mais de 3 meses (cria e cancela um Pix com liberacao em +100 dias);
//   3. mudar a data de liberacao depois do pagamento (evento adiado);
//   4. estornar antes da liberacao.
// Uso:
//   node --env-file=.env scripts/testar-liberacao-mp.mjs <collector_id> [valor] [email_pagador]
//     collector_id  = mp_user_id da casa em organizacoes_mercado_pago (a casa que recebe)
//     valor         = valor do Pix de teste em reais (padrao 1.00)
//     email_pagador = e-mail do comprador (padrao teste@ingressoudi.com.br)
// Requer no .env: MERCADO_PAGO_ACCESS_TOKEN (token da conta da PLATAFORMA, dona da aplicacao).
// O teste usa dinheiro real se o token for de producao: um Pix de R$ 1,00 que e estornado no fim.
// Nada no banco do Ingressoudi e alterado. O resultado fica tambem em teste-liberacao-mp.log.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { createInterface } from 'node:readline/promises'

const BASE_URL = 'https://api.mercadopago.com'
const LOG = 'teste-liberacao-mp.log'
const token = process.env.MP_TESTE_ACCESS_TOKEN || process.env.MERCADO_PAGO_ACCESS_TOKEN
const applicationId = process.env.MERCADO_PAGO_CLIENT_ID || undefined

const [collectorArg, valorArg, emailArg] = process.argv.slice(2)
const collectorId = Number(collectorArg)
const valor = Math.round(Number(valorArg ?? '1') * 100) / 100
const emailPagador = emailArg || 'teste@ingressoudi.com.br'

if (!token) {
  console.error('Defina MERCADO_PAGO_ACCESS_TOKEN no .env (token da conta da plataforma).')
  process.exit(1)
}
if (!Number.isInteger(collectorId) || collectorId <= 0) {
  console.error('Informe o collector_id (mp_user_id da casa). Ex.: node --env-file=.env scripts/testar-liberacao-mp.mjs 123456789')
  process.exit(1)
}
if (!(valor >= 1)) {
  console.error('Valor minimo do teste: 1.00')
  process.exit(1)
}

writeFileSync(LOG, `Teste de liberacao Mercado Pago - ${new Date().toISOString()}\n`)
const resultados = {}

function log(texto) {
  console.log(texto)
  appendFileSync(LOG, `${texto}\n`)
}

/** ISO 8601 no fuso de Brasilia (-03:00), formato aceito pelo Mercado Pago. */
function isoBrasilia(ms) {
  return new Date(ms - 3 * 60 * 60 * 1000).toISOString().replace('Z', '-03:00')
}

function diasAFrente(dias) {
  return isoBrasilia(Date.now() + dias * 24 * 60 * 60 * 1000)
}

async function mp(metodo, caminho, corpo) {
  const resposta = await fetch(`${BASE_URL}${caminho}`, {
    method: metodo,
    headers: {
      accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Idempotency-Key': randomUUID()
    },
    body: corpo === undefined ? undefined : JSON.stringify(corpo)
  })
  const texto = await resposta.text()
  let dados = null
  try {
    dados = texto ? JSON.parse(texto) : null
  } catch {
    dados = texto
  }
  log(`  ${metodo} ${caminho} -> HTTP ${resposta.status}`)
  if (!resposta.ok) log(`  resposta: ${typeof dados === 'string' ? dados : JSON.stringify(dados)}`)
  return { ok: resposta.ok, status: resposta.status, dados }
}

function pixDoPagamento(dados) {
  const pagamento = dados?.payments?.[0]
  return pagamento?.point_of_interaction?.transaction_data?.qr_code ?? null
}

function liberacoes(dados) {
  return (dados?.disbursements ?? []).map((d) => `${d.collector_id}: ${d.money_release_date ?? 'sem data'} (${d.status ?? '?'})`)
}

function corpoPagamento(referencia, diasRetencao) {
  const taxa = Math.round(valor * 10) / 100
  return {
    ...(applicationId ? { application_id: applicationId } : {}),
    description: 'Teste de liberacao Ingressoudi',
    external_reference: referencia,
    binary_mode: false,
    capture: true,
    payer: { email: emailPagador },
    payments: [
      {
        payment_method_id: 'pix',
        payment_type_id: 'bank_transfer',
        transaction_amount: valor,
        description: 'Teste de liberacao Ingressoudi',
        external_reference: referencia,
        date_of_expiration: isoBrasilia(Date.now() + 30 * 60 * 1000)
      }
    ],
    disbursements: [
      {
        collector_id: collectorId,
        amount: valor,
        application_fee: taxa,
        external_reference: `${referencia}-casa`,
        money_release_date: diasAFrente(diasRetencao)
      }
    ]
  }
}

async function cancelar(id) {
  return mp('PUT', `/v1/advanced_payments/${id}`, { status: 'cancelled' })
}

const leitor = createInterface({ input: process.stdin, output: process.stdout })

// Passo 1: Pix com liberacao em +30 dias.
log('\n[1] Criando pagamento avancado Pix com liberacao em +30 dias...')
const criado = await mp('POST', '/v1/advanced_payments', corpoPagamento(`teste-lib-${Date.now()}`, 30))
resultados['1. Criar com Pix e money_release_date'] = criado.ok ? 'SIM' : `NAO (HTTP ${criado.status})`
if (!criado.ok) {
  log('\nA conta nao conseguiu criar o pagamento avancado. Envie este log ao comercial do Mercado Pago.')
  finalizar()
}
const id = criado.dados.id
log(`  id: ${id} | status: ${criado.dados.status}`)
for (const linha of liberacoes(criado.dados)) log(`  liberacao: ${linha}`)

// Passo 2: retencao longa (+100 dias), criado e cancelado sem pagar.
log('\n[2] Testando retencao de +100 dias (cria e cancela, sem pagar)...')
const longo = await mp('POST', '/v1/advanced_payments', corpoPagamento(`teste-lib-longo-${Date.now()}`, 100))
resultados['2. Aceita retencao de 100 dias'] = longo.ok ? 'SIM' : `NAO (HTTP ${longo.status})`
if (longo.ok) {
  for (const linha of liberacoes(longo.dados)) log(`  liberacao: ${linha}`)
  await cancelar(longo.dados.id)
}

// Passo 3: pagar o Pix do passo 1.
const copiaECola = pixDoPagamento(criado.dados)
if (!copiaECola) {
  log('\nO Mercado Pago nao devolveu o Pix copia e cola. Veja a resposta completa abaixo.')
  log(JSON.stringify(criado.dados, null, 2))
  await cancelar(id)
  finalizar()
}
log(`\n[3] Pague este Pix de R$ ${valor.toFixed(2)} pelo app do banco (copia e cola):\n\n${copiaECola}\n`)
await leitor.question('Depois de pagar, aperte Enter para continuar (ou Ctrl+C para sair)... ')

let atual = null
for (let tentativa = 0; tentativa < 30; tentativa += 1) {
  atual = await mp('GET', `/v1/advanced_payments/${id}`)
  const statusPix = atual.dados?.payments?.[0]?.status
  log(`  status: ${atual.dados?.status} | Pix: ${statusPix}`)
  if (statusPix === 'approved') break
  await new Promise((r) => setTimeout(r, 10000))
}
if (atual?.dados?.payments?.[0]?.status !== 'approved') {
  log('\nO Pix nao foi aprovado em 5 minutos. Cancelando o pagamento.')
  await cancelar(id)
  finalizar()
}
for (const linha of liberacoes(atual.dados)) log(`  liberacao apos pagar: ${linha}`)

// Passo 4: mudar a data de liberacao (evento adiado).
log('\n[4] Mudando a data de liberacao para +45 dias...')
const novaData = diasAFrente(45)
const mudou = await mp('POST', `/v1/advanced_payments/${id}/disburses`, { money_release_date: novaData })
const conferido = await mp('GET', `/v1/advanced_payments/${id}`)
for (const linha of liberacoes(conferido.dados)) log(`  liberacao agora: ${linha}`)
resultados['3. Mudar a data depois de pago'] = mudou.ok ? 'SIM (confira a data acima)' : `NAO (HTTP ${mudou.status})`

// Passo 5: estornar antes da liberacao.
log('\n[5] Estornando o pagamento inteiro (o dinheiro volta para quem pagou)...')
const estorno = await mp('POST', `/v1/advanced_payments/${id}/refunds`, {})
resultados['4. Estornar antes da liberacao'] = estorno.ok ? 'SIM' : `NAO (HTTP ${estorno.status})`
if (!estorno.ok) log('  ATENCAO: estorne manualmente pelo painel do Mercado Pago da casa.')

finalizar()

function finalizar() {
  log('\n===== RESUMO =====')
  for (const [pergunta, resposta] of Object.entries(resultados)) log(`${pergunta}: ${resposta}`)
  log(`\nLog completo em ${LOG}. Envie este arquivo ao Claude.`)
  leitor.close()
  process.exit(0)
}
