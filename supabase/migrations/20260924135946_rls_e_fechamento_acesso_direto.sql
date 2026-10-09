-- =============================================================================
-- GZ1 Ingresso - RLS e fechamento de acesso direto
-- Migration: rls_e_fechamento_acesso_direto
--
-- Objetivo: DENY BY DEFAULT. anon/authenticated perdem acesso direto as tabelas
-- e a sequence. RLS habilitada (sem FORCE) para preservar as implementacoes
-- private SECURITY DEFINER (owner postgres, rolbypassrls=true).
--
-- Unica abertura: authenticated pode SELECT a propria linha em public.usuarios.
--
-- Nao cria policies de catalogo/admin/portaria (etapas futuras). Nao altera
-- logica. Nao usa FORCE ROW LEVEL SECURITY. Sem DROP/DELETE/TRUNCATE.
-- =============================================================================

-- 1) RLS nas 10 tabelas (sem FORCE) -------------------------------------------
alter table public.usuarios enable row level security;
alter table public.eventos enable row level security;
alter table public.lotes enable row level security;
alter table public.pedidos enable row level security;
alter table public.ingressos enable row level security;
alter table public.pagamentos enable row level security;
alter table public.entradas enable row level security;
alter table public.cancelamentos_reembolsos enable row level security;
alter table public.tentativas_entrada enable row level security;
alter table public.auditoria enable row level security;

-- 2) Revogar acesso direto de anon/authenticated ------------------------------
revoke all privileges on table public.usuarios from anon, authenticated;
revoke all privileges on table public.eventos from anon, authenticated;
revoke all privileges on table public.lotes from anon, authenticated;
revoke all privileges on table public.pedidos from anon, authenticated;
revoke all privileges on table public.ingressos from anon, authenticated;
revoke all privileges on table public.pagamentos from anon, authenticated;
revoke all privileges on table public.entradas from anon, authenticated;
revoke all privileges on table public.cancelamentos_reembolsos from anon, authenticated;
revoke all privileges on table public.tentativas_entrada from anon, authenticated;
revoke all privileges on table public.auditoria from anon, authenticated;

-- 3) Sequence: compra usa nextval como owner (private DEFINER) ----------------
revoke all privileges on sequence public.seq_pedido_codigo from anon, authenticated;

-- 4) Unica leitura permitida: usuarios (propria linha) ------------------------
grant select on table public.usuarios to authenticated;

create policy usuarios_select_proprio
  on public.usuarios
  for select
  to authenticated
  using (auth.uid() = id);

-- 5) Default privileges: nao abrir objetos futuros automaticamente ------------
-- owner das migrations/objetos = postgres (confirmado no inventario)
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
