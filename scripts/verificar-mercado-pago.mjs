// Ingressoudi - verifica se a conexao com o Mercado Pago esta funcionando.
// SOMENTE LEITURA: nao cria cobranca, nao altera o banco.
//   1. lista as casas conectadas (organizacoes_mercado_pago) e a validade do token;
//   2. testa o token de cada casa no Mercado Pago (GET /users/me);
//   3. testa o token da plataforma (MERCADO_PAGO_ACCESS_TOKEN), se existir;
//   4. mostra os ultimos Pix do Mercado Pago gravados no banco;
//   5. confere no Mercado Pago o status real dos Pix que seguem PENDENTE com reserva vencida.
// Uso:
//   node --env-file=.env scripts/verificar-mercado-pago.mjs
// Requer no .env: SUPABASE_DB_URL, INGRESSOUDI_PROJECT_REF e MERCADO_PAGO_TOKEN_KEY.
import { createDecipheriv, createHash } from 'node:crypto'
import pg from 'pg'

const url = process.env.SUPABASE_DB_URL
const ref = process.env.INGRESSOUDI_PROJECT_REF
const chaveToken = process.env.MERCADO_PAGO_TOKEN_KEY || ''
const tokenPlataforma = process.env.MERCADO_PAGO_ACCESS_TOKEN || ''
const GZ1_PROJECT_REF = 'bzifmlghktciwnlpvlju'

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

// Mesmo formato de server/utils/mercado-pago-cripto.ts (AES-256-GCM, prefixo v1).
function decifrarToken(valor) {
  const partes = String(valor ?? '').split('.')
  if (partes.length !== 4 || partes[0] !== 'v1') throw new Error('token cifrado em formato invalido')
  const [, iv, tag, conteudo] = partes
  const chave = createHash('sha256').update(`token:${chaveToken}`).digest()
  const decipher = createDecipheriv('aes-256-gcm', chave, Buffer.from(iv, 'base64url'))
  decipher.setAuthTag(Buffer.from(tag, 'base64url'))
  return Buffer.concat([decipher.update(Buffer.from(conteudo, 'base64url')), decipher.final()]).toString('utf8')
}

async function testarToken(token) {
  try {
    const resposta = await fetch('https://api.mercadopago.com/users/me', {
      headers: { Authorization: `Bearer ${token}` }
    })
    if (!resposta.ok) return `FALHOU (HTTP ${resposta.status})`
    const dados = await resposta.json()
    return `OK (conta ${dados.id}${dados.nickname ? ` / ${dados.nickname}` : ''})`
  } catch (erro) {
    return `FALHOU (${erro instanceof Error ? erro.message : 'erro de rede'})`
  }
}

function dataBr(valor) {
  if (!valor) return '-'
  return new Date(valor).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' })
}

function diasAte(valor) {
  if (!valor) return 'sem data'
  const dias = Math.floor((Date.parse(valor) - Date.now()) / 86400000)
  return dias < 0 ? `VENCIDO ha ${-dias} dia(s)` : `vence em ${dias} dia(s)`
}

const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
await client.connect()

try {
  console.log('\n=== Casas conectadas ao Mercado Pago ===')
  const { rows: conexoes } = await client.query(`
    select o.slug, m.mp_user_id, m.live_mode, m.expira_em, m.conectado_em,
           m.access_token_cifrado, m.refresh_token_cifrado is not null as tem_refresh
      from public.organizacoes_mercado_pago m
      join public.organizacoes o on o.id = m.organizacao_id
     order by o.slug`)
  if (!conexoes.length) console.log('Nenhuma casa conectada.')
  for (const c of conexoes) {
    let teste
    try {
      teste = await testarToken(decifrarToken(c.access_token_cifrado))
    } catch (erro) {
      teste = `NAO TESTADO (${erro instanceof Error ? erro.message : 'erro'})`
    }
    console.log(`- ${c.slug}: conta MP ${c.mp_user_id}, ${c.live_mode ? 'producao' : 'TESTE'}, ` +
      `token ${diasAte(c.expira_em)}, renovacao automatica ${c.tem_refresh ? 'sim' : 'NAO'}`)
    console.log(`    teste no Mercado Pago: ${teste}`)
  }

  console.log('\n=== Token da plataforma ===')
  console.log(tokenPlataforma ? `teste no Mercado Pago: ${await testarToken(tokenPlataforma)}` : 'nao configurado no .env')

  console.log('\n=== Ultimos 10 Pix do Mercado Pago no banco ===')
  const { rows: pagamentos } = await client.query(`
    select o.slug, p.valor, p.status, p.criado_em, p.confirmado_em
      from public.pagamentos p
      join public.organizacoes o on o.id = p.organizacao_id
     where p.provedor = 'MERCADO_PAGO'
     order by p.criado_em desc
     limit 10`)
  if (!pagamentos.length) console.log('Nenhum Pix do Mercado Pago encontrado.')
  for (const p of pagamentos) {
    console.log(`- ${dataBr(p.criado_em)}  ${p.slug}  R$ ${Number(p.valor).toFixed(2)}  ${p.status}` +
      (p.confirmado_em ? `  (confirmado ${dataBr(p.confirmado_em)})` : ''))
  }

  console.log('\n=== Pix PENDENTE com reserva vencida (status real no Mercado Pago) ===')
  const { rows: pendentes } = await client.query(`
    select o.slug, p.valor, p.cobranca_id, p.criado_em, pe.codigo, pe.status as pedido_status,
           m.access_token_cifrado
      from public.pagamentos p
      join public.pedidos pe on pe.id = p.pedido_id
      join public.organizacoes o on o.id = p.organizacao_id
      left join public.organizacoes_mercado_pago m on m.organizacao_id = p.organizacao_id
     where p.provedor = 'MERCADO_PAGO' and p.status = 'PENDENTE'
       and pe.reserva_expira_em < now()
     order by p.criado_em desc`)
  if (!pendentes.length) console.log('Nenhum.')
  for (const p of pendentes) {
    let real = 'nao consultado'
    try {
      if (!p.cobranca_id || !p.access_token_cifrado) throw new Error('sem cobranca_id ou sem conexao')
      const resposta = await fetch(`https://api.mercadopago.com/v1/payments/${encodeURIComponent(p.cobranca_id)}`, {
        headers: { Authorization: `Bearer ${decifrarToken(p.access_token_cifrado)}` }
      })
      real = resposta.ok ? (await resposta.json()).status : `HTTP ${resposta.status}`
    } catch (erro) {
      real = `nao consultado (${erro instanceof Error ? erro.message : 'erro'})`
    }
    console.log(`- ${dataBr(p.criado_em)}  ${p.slug}  pedido ${p.codigo} (${p.pedido_status})  ` +
      `R$ ${Number(p.valor).toFixed(2)}  -> no Mercado Pago: ${real}`)
  }
  console.log('')
} finally {
  await client.end()
}
