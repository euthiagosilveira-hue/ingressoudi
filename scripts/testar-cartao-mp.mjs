// Ingressoudi - teste do pagamento com CARTAO no ambiente de testes (sandbox) do Mercado Pago.
// Nao usa dinheiro real e nao altera o banco do Ingressoudi.
// Responde, antes de programar o cartao no app:
//   1. o cartao aprovado aceita a taxa da plataforma (application_fee)?
//   2. quais parcelas (ate 3x) e juros aparecem para R$ 100?
//   3. como chegam as recusas (status_detail) para as mensagens em portugues;
//   4. "em analise" com e sem binary_mode;
//   5. 3DS (three_d_secure_mode: optional) junto com binary_mode da erro?
//   6. a chave de idempotencia devolve o mesmo pagamento na repeticao?
//   7. o estorno total do cartao funciona?
//   8. cancelar um Pix aberto antes de cobrar o cartao funciona?
// Uso (credenciais de TESTE do vendedor, em Suas integracoes > Credenciais de teste):
//   node --env-file=.env scripts/testar-cartao-mp.mjs
// Requer no .env: MP_TESTE_ACCESS_TOKEN e MP_TESTE_PUBLIC_KEY (de teste, nunca as de producao).
// Opcional: MP_TESTE_EMAIL_COMPRADOR (qualquer e-mail diferente do da conta; nao use e-mail de usuario de teste).
// IMPORTANTE: use as "Credenciais de teste" da SUA conta real. As credenciais de um usuario de teste
// (TESTUSER...) sao tratadas como de producao e o MP responde 401 "Unauthorized use of live credentials".
// O resultado fica tambem em teste-cartao-mp.log, na pasta do projeto.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'

const BASE_URL = 'https://api.mercadopago.com'
const LOG = 'teste-cartao-mp.log'
const token = process.env.MP_TESTE_ACCESS_TOKEN || ''
const publicKey = process.env.MP_TESTE_PUBLIC_KEY || ''
const emailComprador = process.env.MP_TESTE_EMAIL_COMPRADOR || 'comprador.teste@ingressoudi.com.br'

// Cartoes de teste oficiais do Mercado Pago (Brasil). O nome do titular define o resultado.
const MASTER = { numero: '5031433215406351', cvv: '123', bandeira: 'master' }
const CPF_TESTE = '12345678909'

if (!token || !publicKey) {
  console.error('Defina MP_TESTE_ACCESS_TOKEN e MP_TESTE_PUBLIC_KEY no .env (credenciais de TESTE).')
  process.exit(1)
}

writeFileSync(LOG, `Teste de cartao Mercado Pago (sandbox) - ${new Date().toISOString()}\n`)
const resumo = []

function log(texto) {
  console.log(texto)
  appendFileSync(LOG, `${texto}\n`)
}

function registrar(pergunta, resposta) {
  resumo.push(`${pergunta}: ${resposta}`)
}

async function mp(metodo, caminho, corpo, { chave, autenticar = true } = {}) {
  const headers = { accept: 'application/json', 'Content-Type': 'application/json' }
  if (autenticar) headers.Authorization = `Bearer ${token}`
  if (metodo !== 'GET') headers['X-Idempotency-Key'] = chave || randomUUID()
  const resposta = await fetch(`${BASE_URL}${caminho}`, {
    method: metodo,
    headers,
    body: corpo === undefined ? undefined : JSON.stringify(corpo)
  })
  const texto = await resposta.text()
  let dados = null
  try {
    dados = texto ? JSON.parse(texto) : null
  } catch {
    dados = texto
  }
  log(`  ${metodo} ${caminho.split('?')[0]} -> HTTP ${resposta.status}`)
  if (!resposta.ok) log(`  resposta: ${typeof dados === 'string' ? dados : JSON.stringify(dados).slice(0, 800)}`)
  return { ok: resposta.ok, status: resposta.status, dados }
}

function isoBrasilia(ms) {
  return new Date(ms - 3 * 60 * 60 * 1000).toISOString().replace('Z', '-03:00')
}

/** Trava de seguranca: so roda com conta de teste. */
async function conferirContaDeTeste() {
  log('\n[0] Conferindo se a credencial e de TESTE')
  const r = await mp('GET', '/users/me')
  if (!r.ok) {
    log('  Nao foi possivel ler a conta. Confira o MP_TESTE_ACCESS_TOKEN.')
    process.exit(1)
  }
  const tags = Array.isArray(r.dados?.tags) ? r.dados.tags : []
  const ehTeste = token.startsWith('TEST-') || tags.includes('test_user')
  if (tags.includes('test_user') && !token.startsWith('TEST-')) {
    log('  AVISO: esta e a credencial de um USUARIO de teste. Para cartao, o Mercado Pago pede as')
    log('  "Credenciais de teste" da sua conta real (comecam com TEST-). Os pagamentos devem dar 401.')
  }
  log(`  conta ${r.dados?.id} (${r.dados?.nickname ?? '?'}), tags: ${tags.join(', ') || 'nenhuma'}`)
  if (!ehTeste) {
    log('  BLOQUEADO: a credencial parece ser de PRODUCAO. Use as credenciais de teste.')
    process.exit(1)
  }
  return r.dados
}

async function tokenDoCartao(titular) {
  const ano = new Date().getFullYear() + 3
  const r = await mp(
    'POST',
    `/v1/card_tokens?public_key=${encodeURIComponent(publicKey)}`,
    {
      card_number: MASTER.numero,
      security_code: MASTER.cvv,
      expiration_month: 11,
      expiration_year: ano,
      cardholder: { name: titular, identification: { type: 'CPF', number: CPF_TESTE } }
    },
    { autenticar: false }
  )
  if (!r.ok || !r.dados?.id) throw new Error(`Falha ao gerar token do cartao (${titular}).`)
  return r.dados.id
}

function corpoCartao(cardToken, extra = {}) {
  return {
    transaction_amount: 100,
    token: cardToken,
    description: 'Teste cartao Ingressoudi',
    installments: 1,
    payment_method_id: MASTER.bandeira,
    external_reference: `teste-cartao-${randomUUID()}`,
    statement_descriptor: 'INGRESSOUDI',
    payer: {
      email: emailComprador,
      first_name: 'Comprador',
      last_name: 'Teste',
      identification: { type: 'CPF', number: CPF_TESTE }
    },
    additional_info: {
      items: [{ id: 'ingresso', title: 'Ingresso Pista - teste', quantity: 1, unit_price: 100 }],
      payer: { first_name: 'Comprador', last_name: 'Teste', phone: { area_code: '34', number: '999999999' } }
    },
    ...extra
  }
}

function descrever(p) {
  return `status=${p?.status} detalhe=${p?.status_detail} id=${p?.id} taxa=${p?.application_fee ?? p?.marketplace_fee ?? '-'}`
}

async function pagar(titulo, titular, extra, opcoes) {
  log(`\n${titulo}`)
  const cardToken = await tokenDoCartao(titular)
  const r = await mp('POST', '/v1/payments', corpoCartao(cardToken, extra), opcoes)
  if (r.ok) log(`  ${descrever(r.dados)}`)
  return r
}

async function main() {
  await conferirContaDeTeste()

  // 1) Aprovado a vista com taxa da plataforma.
  let aprovado = await pagar('[1] Aprovado a vista, com application_fee R$ 1,00 e binary_mode', 'APRO', {
    application_fee: 1,
    binary_mode: true
  })
  if (aprovado.ok) {
    registrar('1. Cartao aprovado com taxa da plataforma', `SIM (${aprovado.dados.status})`)
  } else {
    registrar('1. Cartao aprovado com taxa da plataforma', `NAO, HTTP ${aprovado.status} (ver log)`)
    aprovado = await pagar('[1b] Aprovado a vista SEM application_fee (para comparar)', 'APRO', { binary_mode: true })
    registrar('1b. Cartao aprovado sem taxa', aprovado.ok ? `SIM (${aprovado.dados.status})` : `NAO, HTTP ${aprovado.status}`)
  }

  // 2) Parcelas para R$ 100.
  log('\n[2] Parcelas disponiveis para R$ 100 (bin 503143)')
  const parcelas = await mp('GET', `/v1/payment_methods/installments?amount=100&bin=50314332`)
  const custos = parcelas.ok ? (parcelas.dados?.[0]?.payer_costs ?? []) : []
  for (const c of custos.filter((c) => c.installments <= 3)) {
    log(`  ${c.installments}x de R$ ${c.installment_amount} = R$ ${c.total_amount} (juros ${c.installment_rate}%)`)
  }
  registrar('2. Parcelas ate 3x', custos.length ? custos.filter((c) => c.installments <= 3).map((c) => `${c.installments}x=R$${c.total_amount}`).join(', ') : 'nao retornou')
  const tres = await pagar('[2b] Pagamento em 3x', 'APRO', { installments: 3, application_fee: 1, binary_mode: true })
  registrar('2b. Pagamento em 3x', tres.ok ? `${tres.dados.status}, total pago pelo comprador R$ ${tres.dados.transaction_details?.total_paid_amount ?? '?'}` : `HTTP ${tres.status}`)

  // 3) Recusas.
  const recusas = []
  for (const [titular, nome] of [['OTHE', 'recusado geral'], ['FUND', 'saldo insuficiente'], ['SECU', 'CVV invalido'], ['EXPI', 'data de validade'], ['FORM', 'erro no formulario']]) {
    const r = await pagar(`[3] Recusa: ${nome} (${titular})`, titular, { binary_mode: true })
    recusas.push(`${nome}=${r.ok ? r.dados.status_detail : `HTTP ${r.status}`}`)
  }
  registrar('3. Recusas (status_detail)', recusas.join('; '))

  // 4) Em analise.
  const analiseSem = await pagar('[4] Em analise (CONT) sem binary_mode', 'CONT', { binary_mode: false })
  const analiseCom = await pagar('[4b] Em analise (CONT) com binary_mode', 'CONT', { binary_mode: true })
  registrar('4. Em analise', `sem binary=${analiseSem.dados?.status ?? analiseSem.status}; com binary=${analiseCom.dados?.status ?? analiseCom.status}`)

  // 5) 3DS.
  const tdsCom = await pagar('[5] 3DS optional + binary_mode', 'APRO', { three_d_secure_mode: 'optional', binary_mode: true })
  const tdsSem = await pagar('[5b] 3DS optional sem binary_mode', 'APRO', { three_d_secure_mode: 'optional', binary_mode: false })
  const tdsInfo = (r) => (r.ok ? `${r.dados.status}/${r.dados.status_detail}${r.dados.three_ds_info ? ' (com desafio 3DS)' : ''}` : `HTTP ${r.status}`)
  registrar('5. 3DS', `com binary=${tdsInfo(tdsCom)}; sem binary=${tdsInfo(tdsSem)}`)

  // 6) Idempotencia.
  log('\n[6] Mesma chave de idempotencia duas vezes')
  const chave = randomUUID()
  const tokenIdem = await tokenDoCartao('APRO')
  const corpoIdem = corpoCartao(tokenIdem, { binary_mode: true })
  const p1 = await mp('POST', '/v1/payments', corpoIdem, { chave })
  const p2 = await mp('POST', '/v1/payments', corpoIdem, { chave })
  const mesmo = p1.ok && p2.ok && String(p1.dados.id) === String(p2.dados.id)
  log(`  primeiro=${p1.dados?.id} segundo=${p2.dados?.id}`)
  registrar('6. Idempotencia devolve o mesmo pagamento', mesmo ? 'SIM' : `NAO (${p1.dados?.id} / ${p2.dados?.id ?? p2.status})`)

  // 7) Estorno.
  if (aprovado.ok && aprovado.dados.status === 'approved') {
    log('\n[7] Estorno total do pagamento aprovado')
    const est = await mp('POST', `/v1/payments/${aprovado.dados.id}/refunds`, {})
    const depois = await mp('GET', `/v1/payments/${aprovado.dados.id}`)
    registrar('7. Estorno total', est.ok ? `SIM (pagamento agora ${depois.dados?.status})` : `NAO, HTTP ${est.status}`)
  } else {
    registrar('7. Estorno total', 'nao testado (sem pagamento aprovado)')
  }

  // 8) Cancelar Pix aberto.
  log('\n[8] Criar Pix e cancelar antes de pagar')
  const pix = await mp('POST', '/v1/payments', {
    transaction_amount: 100,
    description: 'Teste Pix cancelado Ingressoudi',
    payment_method_id: 'pix',
    external_reference: `teste-pix-${randomUUID()}`,
    date_of_expiration: isoBrasilia(Date.now() + 30 * 60 * 1000),
    payer: { email: emailComprador }
  })
  if (pix.ok) {
    const cancel = await mp('PUT', `/v1/payments/${pix.dados.id}`, { status: 'cancelled' })
    registrar('8. Cancelar Pix aberto', cancel.ok ? `SIM (${cancel.dados?.status})` : `NAO, HTTP ${cancel.status}`)
  } else {
    registrar('8. Cancelar Pix aberto', `Pix nao foi criado, HTTP ${pix.status}`)
  }

  log('\n===== RESUMO =====')
  for (const linha of resumo) log(linha)
  log('\nEnvie o arquivo teste-cartao-mp.log para o Claude.')
}

main().catch((erro) => {
  log(`\nERRO: ${erro instanceof Error ? erro.message : String(erro)}`)
  log('\n===== RESUMO PARCIAL =====')
  for (const linha of resumo) log(linha)
  process.exit(1)
})
