-- =============================================================================
-- GZ1 Ingresso - Fundacao de seguranca
-- Migration: fundacao_seguranca
--
-- Objetivo (somente fundacao):
--   * criar schema privado "private" (nao exposto pela Data API);
--   * criar helpers de identidade baseados em auth.uid();
--   * separar funcoes publicas de internas (sem mover nada existente).
--
-- NAO faz nesta migration:
--   * RLS / policies;
--   * REVOKE em tabelas, funcoes ou sequence existentes do schema public;
--   * alteracao de assinaturas de RPCs;
--   * SECURITY DEFINER no schema public;
--   * alteracao de Exposed Schemas;
--   * alteracao de frontend.
--
-- SECURITY DEFINER e usado SOMENTE no schema private, com search_path = '' e
-- objetos schema-qualified. Justificativa: no futuro public.usuarios tera RLS;
-- as policies (executadas pelo papel da sessao) chamarao estes helpers, que
-- precisam ler public.usuarios como owner sem depender de policies.
--
-- Sem DROP/DELETE/TRUNCATE destrutivo.
-- =============================================================================

-- SCHEMA PRIVADO --------------------------------------------------------------
create schema if not exists private;

revoke all on schema private from public;

-- HELPERS DE IDENTIDADE -------------------------------------------------------

-- id do usuario autenticado (auth.uid()). Sem acesso a tabelas: INVOKER.
create or replace function private.usuario_atual_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select auth.uid();
$$;

-- perfil do usuario autenticado; NULL se nao autenticado/inexistente/inativo.
-- SECURITY DEFINER: le public.usuarios independentemente de RLS futura.
create or replace function private.perfil_usuario_atual()
returns public.perfil_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select u.perfil
    from public.usuarios u
   where u.id = auth.uid()
     and u.ativo = true;
$$;

-- true apenas para ADMINISTRADOR ativo autenticado.
create or replace function private.usuario_e_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.perfil_usuario_atual() = 'ADMINISTRADOR', false);
$$;

-- true para ADMINISTRADOR ou PORTARIA ativos autenticados.
create or replace function private.usuario_pode_operar_portaria()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.perfil_usuario_atual() in ('ADMINISTRADOR', 'PORTARIA'),
    false
  );
$$;

-- PERMISSOES DOS HELPERS ------------------------------------------------------
-- Nao expor como RPC. Sem EXECUTE para PUBLIC/anon/authenticated nesta etapa.
-- O owner (postgres) mantem EXECUTE e USAGE no schema private.
-- Quando as policies de RLS forem criadas, sera feito o GRANT minimo
-- (USAGE no schema private + EXECUTE nos helpers) para "authenticated".
revoke execute on function private.usuario_atual_id() from public;
revoke execute on function private.perfil_usuario_atual() from public;
revoke execute on function private.usuario_e_admin() from public;
revoke execute on function private.usuario_pode_operar_portaria() from public;
