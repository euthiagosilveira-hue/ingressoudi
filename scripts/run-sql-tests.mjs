// Ingressoudi - executa os testes SQL de supabase/tests contra o banco do Supabase.
// Uso:   npm run test:db                      (todos os testes)
//        npm run test:db -- supabase/tests/x.test.sql   (arquivos específicos)
// Requer no .env: SUPABASE_DB_URL e INGRESSOUDI_PROJECT_REF.
// Cada arquivo roda numa conexão própria; os testes usam begin/rollback e não persistem dados.
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import pg from 'pg'

const url = process.env.SUPABASE_DB_URL
const ref = process.env.INGRESSOUDI_PROJECT_REF

if (!url || !ref) {
  console.error('Defina SUPABASE_DB_URL e INGRESSOUDI_PROJECT_REF no .env')
  process.exit(1)
}
// Trava de segurança: só roda se a URL for do projeto do Ingressoudi.
if (!url.includes(ref)) {
  console.error('SUPABASE_DB_URL não pertence ao projeto INGRESSOUDI_PROJECT_REF. Abortado.')
  process.exit(1)
}

const dir = 'supabase/tests'
const args = process.argv.slice(2)
const files = args.length
  ? args
  : readdirSync(dir).filter((f) => f.endsWith('.sql')).sort().map((f) => join(dir, f))

const resultados = []
for (const arquivo of files) {
  const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
  try {
    await client.connect()
    await client.query(readFileSync(arquivo, 'utf8'))
    resultados.push({ arquivo, resultado: 'PASSOU', erro: '' })
  } catch (e) {
    resultados.push({ arquivo, resultado: 'FALHOU', erro: String(e.message).slice(0, 300) })
  } finally {
    await client.end().catch(() => {})
  }
}

console.table(resultados)
const falhas = resultados.filter((r) => r.resultado === 'FALHOU').length
console.log(`${resultados.length - falhas} passaram, ${falhas} falharam`)
process.exit(falhas ? 1 : 0)
