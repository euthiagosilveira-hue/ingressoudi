// Ingressoudi - remove DEFINITIVAMENTE uma organizacao (casa) de teste e todos os dados dela.
// Uso:
//   node --env-file=.env scripts/remover-organizacao.mjs <slug>
//       -> somente leitura: mostra o que existe na organizacao (nada e apagado)
//   node --env-file=.env scripts/remover-organizacao.mjs <slug> --confirmar <slug>
//       -> apaga tudo numa unica transacao (se qualquer passo falhar, nada e apagado)
// Contas de login (auth.users / public.usuarios) NAO sao apagadas; so perdem o vinculo.
// Requer no .env: SUPABASE_DB_URL e INGRESSOUDI_PROJECT_REF.
import { readFileSync } from 'node:fs'
import pg from 'pg'

const url = process.env.SUPABASE_DB_URL
const ref = process.env.INGRESSOUDI_PROJECT_REF
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

const [slug, flag, confirmacao] = process.argv.slice(2)
if (!slug || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) {
  console.error('Informe o slug da organizacao (ex.: casa-teste).')
  process.exit(1)
}
const remover = flag === '--confirmar'
if (remover && confirmacao !== slug) {
  console.error(`Para remover, repita o slug: --confirmar ${slug}`)
  process.exit(1)
}

const ler = (arquivo) =>
  readFileSync(new URL(`./sql/${arquivo}`, import.meta.url), 'utf8').replaceAll('__SLUG__', slug)

const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
client.on('notice', (n) => console.log('  ' + n.message))

try {
  await client.connect()
  const { rows } = await client.query(ler('organizacao-resumo.sql'))
  const resumo = JSON.parse(rows[0].resumo)
  if (!resumo.organizacao) {
    console.error(`Organizacao "${slug}" nao encontrada.`)
    process.exit(1)
  }
  console.log(`Projeto: ${ref}`)
  console.log(JSON.stringify(resumo, null, 2))

  if (!remover) {
    console.log(`\nNada foi apagado. Para remover: node --env-file=.env scripts/remover-organizacao.mjs ${slug} --confirmar ${slug}`)
  } else {
    console.log(`\nRemovendo "${slug}"...`)
    await client.query('begin')
    await client.query(ler('organizacao-remover.sql'))
    await client.query('commit')
    const { rows: depois } = await client.query('select count(*)::int as n from public.organizacoes where slug = $1', [slug])
    console.log(depois[0].n === 0 ? 'Concluido: organizacao removida.' : 'ATENCAO: a organizacao ainda existe.')
  }
} catch (e) {
  await client.query('rollback').catch(() => {})
  console.error('ERRO (nada foi apagado): ' + String(e.message))
  process.exitCode = 1
} finally {
  await client.end().catch(() => {})
}
