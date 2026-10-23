// Ingressoudi - teste de ponta a ponta de um Pix REAL numa casa conectada, com estorno no fim.
//   1. le o token Mercado Pago da casa (organizacoes_mercado_pago, somente leitura);
//   2. cria um Pix real com esse token (mesmo caminho que o app usa nas vendas);
//   3. mostra o Pix copia e cola e espera o pagamento (ate 30 minutos);
//   4. estorna o valor total e confere o estorno.
// Nada e gravado no banco do Ingressoudi (o webhook ignora pagamentos que nao sao do app).
// Uso:
//   node --env-file=.env scripts/testar-pagamento-mp.mjs <slug> [valor] [email_pagador]
//     slug          = slug da casa (ex.: galeria)
//     valor         = valor do Pix em reais (padrao 1.00)
//     email_pagador = e-mail do comprador (padrao teste@ingressoudi.com.br)
// Requer no .env: SUPABASE_DB_URL, INGRESSOUDI_PROJECT_REF e MERCADO_PAGO_TOKEN_KEY.
// Atencao: o Pix precisa ser pago de uma conta DIFERENTE da conta Mercado Pago da casa.
// O resultado fica tambem em teste-pagamento-mp.log (sem tokens).
import { appendFileSync, writeFileSync } from 'node:fs'
import { createDecipheriv, createHash, randomUUID } from 'node:crypto'
import pg from 'pg'

const BASE_URL = 'https://api.mercadopago.com'
const LOG = 'teste-pagamento-mp.log'
const ESPERA_MAXIMA_MS = 30 * 60 * 1000
const GZ1_PROJECT_REF = 'bzifmlghktciwnlpvlju'

const url = process.env.SUPABASE_DB_URL
const ref = process.env.INGRESSOUDI_PROJECT_REF
const chaveToken = process.env.MERCADO_PAGO_TOKEN_KEY || ''

const [slug, valorArg, emailArg] = process.argv.slice(2)
const valor = Math.round(Number(valorArg ?? '1') * 100) / 100
const emailPagador = emailArg || 'teste@ingressoudi.com.br'

if (!url || !ref) {
  console.error('Defina SUPABASE_DB_URL e INGRESSOUDI_PROJECT_REF no .env')
  process.exit(1)
}
if (ref === GZ1_PROJECT_REF || url.includes(GZ1_PROJECT_REF)) {
  console.error('BLOQUEADO: o .env aponta para o projeto do GZ1.')
  process.exit(1)
}
if (!url.includes(ref)) {
  console.error('SUPABASE_DB_URL nao pertence ao projeto INGRESSOUDI_PROJECT_REF. Abortado.')
  process.exit(1)
}
if (!slug || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) {
  console.error('Informe o slug da casa. Ex.: node --env-file=.env scripts/testar-pagamento-mp.mjs galeria')
  process.exit(1)
}
if (!(valor >= 1)) {
  console.error('Valor minimo do teste: 1.00')
  process.exit(1)
}

writeFileSync(LOG, `Teste de pagamento Mercado Pago - ${new Date().toISOString()}\n`)

function log(texto) {
  console.log(texto)
  appendFileSync(LOG, `${texto}\n`)
}

const esperar = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// Mesmo formato de server/utils/mercado-pago-cripto.ts (AES-256-GCM, prefixo v1).
function decifrarToken(valorCifrado) {
  const partes = String(valorCifrado ?? '').split('.')
  if (partes.length !== 4 || partes[0] !== 'v1') throw new Error('token cifrado em formato invalido')
  const [, iv, tag, conteudo] = partes
  const chave = createHash('sha256').update(`token:${chaveToken}`).digest()
  const decipher = createDecipheriv('aes-256-gcm', chave, Buffer.from(iv, 'base64url'))
  decipher.setAuthTag(Buffer.from(tag, 'base64url'))
  return Buffer.concat([decipher.update(Buffer.from(conteudo, 'base64url')), decipher.final()]).toString('utf8')
}

/** ISO 8601 no fuso de Brasilia (-03:00), formato aceito pelo Mercado Pago. */
function isoBrasilia(ms) {
  return new Date(ms - 3 * 60 * 60 * 1000).toISOString().replace('Z', '-03:00')
}

async function mp(token, metodo, caminho, corpo, extras = {}) {
  const resposta = await fetch(`${BASE_URL}${caminho}`, {
    method: metodo,
    headers: {
      accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...extras
    },
    body: corpo === undefined ? undefined : JSON.stringify(corpo)
  })
  const texto = await resposta.text()
  let dados = null
  try {
    dados = texto ? JSON.parse(texto) : null
  } catch {
    dados = { bruto: texto.slice(0, 500) }
  }
  return { ok: resposta.ok, status: resposta.status, dados }
}

function erroMp(r) {
  const d = r.dados ?? {}
  const causas = Array.isArray(d.cause) ? d.cause.map((c) => `${c.code ?? ''} ${c.description ?? ''}`.trim()) : []
  return `HTTP ${r.status} ${[d.message, d.error, ...causas].filter(Boolean).join(' | ')}`.trim()
}

// 1) Token da casa ----------------------------------------------------------------
const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
await client.connect()
let conexao
try {
  const { rows } = await client.query(
    `select o.slug, o.nome, m.mp_user_id, m.live_mode, m.access_token_cifrado
       from public.organizacoes_mercado_pago m
       join public.organizacoes o on o.id = m.organizacao_id
      where o.slug = $1`,
    [slug]
  )
  conexao = rows[0]
} finally {
  await client.end()
}
if (!conexao) {
  log(`A casa "${slug}" nao existe ou nao conectou o Mercado Pago.`)
  process.exit(1)
}
const token = decifrarToken(conexao.access_token_cifrado)
log(`Casa: ${conexao.nome} (${conexao.slug}), conta MP ${conexao.mp_user_id}, ${conexao.live_mode ? 'producao' : 'TESTE'}`)

// 2) Cria o Pix -------------------------------------------------------------------
const referencia = `teste-pagamento-${conexao.slug}-${Date.now()}`
const criado = await mp(
  token,
  'POST',
  '/v1/payments',
  {
    transaction_amount: valor,
    description: 'Teste Ingressoudi (sera estornado)',
    payment_method_id: 'pix',
    external_reference: referencia,
    date_of_expiration: isoBrasilia(Date.now() + 30 * 60 * 1000),
    payer: { email: emailPagador }
  },
  { 'X-Idempotency-Key': randomUUID() }
)
if (!criado.ok) {
  log(`[FALHOU] Criar Pix: ${erroMp(criado)}`)
  process.exit(1)
}
const pagamentoId = String(criado.dados.id)
const copiaECola = criado.dados.point_of_interaction?.transaction_data?.qr_code
log(`[OK] Pix criado: pagamento ${pagamentoId}, R$ ${valor.toFixed(2)}, status ${criado.dados.status}`)
log('\nPague este Pix (copia e cola) com uma conta DIFERENTE da conta da casa:\n')
console.log(copiaECola ?? '(o Mercado Pago nao devolveu o copia e cola)')
console.log('\nAguardando o pagamento (ate 30 minutos). Ctrl+C cancela o teste.\n')

// 3) Espera o pagamento -------------------------------------------------------------
const inicio = Date.now()
let pagamento = criado.dados
while (pagamento.status !== 'approved') {
  if (['cancelled', 'rejected', 'refunded', 'charged_back'].includes(pagamento.status)) {
    log(`[FALHOU] Pagamento terminou como ${pagamento.status} (${pagamento.status_detail ?? '-'})`)
    process.exit(1)
  }
  if (Date.now() - inicio > ESPERA_MAXIMA_MS) {
    log('[FALHOU] O Pix nao foi pago em 30 minutos. Ele expira sozinho, nada a estornar.')
    process.exit(1)
  }
  await esperar(5000)
  const consulta = await mp(token, 'GET', `/v1/payments/${pagamentoId}`)
  if (consulta.ok) pagamento = consulta.dados
}
const segundos = Math.round((Date.now() - inicio) / 1000)
log(`[OK] Pagamento aprovado (${segundos}s depois de criado). Valor liquido para a casa: ` +
  `R$ ${Number(pagamento.transaction_details?.net_received_amount ?? 0).toFixed(2)}`)

// 4) Estorno ----------------------------------------------------------------------
await esperar(5000)
const estorno = await mp(token, 'POST', `/v1/payments/${pagamentoId}/refunds`, {}, {
  'X-Idempotency-Key': randomUUID(),
  'X-Render-In-Process-Refunds': 'true'
})
if (!estorno.ok) {
  log(`[FALHOU] Estorno: ${erroMp(estorno)}`)
  log(`Faca o estorno manual no painel do Mercado Pago da casa (pagamento ${pagamentoId}).`)
  process.exit(1)
}
log(`[OK] Estorno pedido: reembolso ${estorno.dados.id}, status ${estorno.dados.status}, R$ ${Number(estorno.dados.amount ?? valor).toFixed(2)}`)

for (let i = 0; i < 12; i += 1) {
  await esperar(5000)
  const consulta = await mp(token, 'GET', `/v1/payments/${pagamentoId}`)
  if (consulta.ok && consulta.dados.status === 'refunded') {
    log('[OK] Pagamento estornado: o dinheiro volta para quem pagou.')
    log('\nRESULTADO: conexao da casa funcionando de ponta a ponta (criar Pix, receber, estornar).')
    process.exit(0)
  }
}
log('[AVISO] O estorno foi aceito mas ainda esta em processamento. Confira o pagamento no painel do Mercado Pago em alguns minutos.')
