// Ingressoudi - SOMENTE LEITURA: lista tabelas do schema public que NAO fazem
// parte das migrations do Ingressoudi (ex.: criadas a mao no painel) e mostra
// colunas, quantidade de linhas, RLS, politicas, permissoes e dependencias.
// Uso: node --env-file=.env scripts/inspecionar-tabelas-avulsas.mjs
import pg from 'pg'

const url = process.env.SUPABASE_DB_URL
const ref = process.env.INGRESSOUDI_PROJECT_REF
if (!url || !ref || ref === 'bzifmlghktciwnlpvlju' || url.includes('bzifmlghktciwnlpvlju') || !url.includes(ref)) {
  console.error('Abortado: confira SUPABASE_DB_URL / INGRESSOUDI_PROJECT_REF (nunca o GZ1).')
  process.exit(1)
}

const CONHECIDAS = [
  'auditoria', 'cancelamentos_reembolsos', 'compartilhamentos_ingresso', 'entradas', 'entradas_vip',
  'eventos', 'ingressos', 'lista_vip', 'lotes', 'membros_organizacao', 'organizacoes',
  'organizacoes_mercado_pago', 'pagamentos', 'pedidos', 'recuperacoes_ingressos',
  'tentativas_entrada', 'tentativas_recuperacao', 'usuarios'
]

const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
try {
  await client.connect()
  await client.query('begin read only')
  const { rows: tabelas } = await client.query(
    `select c.oid, c.relname, pg_get_userbyid(c.relowner) as dono, c.relrowsecurity as rls
       from pg_class c
      where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
        and c.relname <> all($1::text[])
      order by c.relname`, [CONHECIDAS])
  console.log(`Projeto: ${ref}`)
  if (tabelas.length === 0) console.log('Nenhuma tabela avulsa encontrada.')
  for (const t of tabelas) {
    const nome = t.relname
    const cols = await client.query(
      `select column_name, data_type from information_schema.columns
        where table_schema='public' and table_name=$1 order by ordinal_position`, [nome])
    const qtd = await client.query(`select count(*)::int as n from public.${client.escapeIdentifier(nome)}`)
    const pols = await client.query(`select polname, polcmd from pg_policy where polrelid=$1`, [t.oid])
    const fks = await client.query(
      `select conrelid::regclass::text as de, confrelid::regclass::text as para
         from pg_constraint where contype='f' and (conrelid=$1 or confrelid=$1)`, [t.oid])
    const funcs = await client.query(
      `select p.oid::regprocedure::text as f from pg_proc p
        where p.pronamespace in ('public'::regnamespace,'private'::regnamespace)
          and p.prosrc ~* ('\\m(public\\.)?' || $1 || '\\M')`, [nome])
    console.log('\n=== ' + nome)
    console.log(JSON.stringify({
      dono: t.dono,
      rls_ligada: t.rls,
      linhas: qtd.rows[0].n,
      colunas: cols.rows.map((c) => `${c.column_name} (${c.data_type})`),
      politicas: pols.rows,
      chaves_estrangeiras: fks.rows,
      funcoes_que_citam: funcs.rows.map((r) => r.f)
    }, null, 2))
  }
  await client.query('rollback')
} catch (e) {
  console.error('ERRO: ' + String(e.message))
  process.exitCode = 1
} finally {
  await client.end().catch(() => {})
}
