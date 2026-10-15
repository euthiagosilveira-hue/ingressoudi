-- =============================================================================
-- Ingressoudi - Testes: guarda de seguranca (RLS e permissoes)
-- Arquivo: supabase/tests/seguranca_acl.test.sql
-- Falha se alguma tabela ficar sem RLS, se anon/authenticated ganharem acesso
-- direto a tabelas ou se funcoes de trigger ficarem executaveis por eles.
-- =============================================================================

begin;

do $$
declare
  v_lista text;
begin
  -- 1) toda tabela do schema public com RLS ligada
  select string_agg(c.relname, ', ') into v_lista
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and not c.relrowsecurity;
  if v_lista is not null then
    raise exception 'Tabelas sem RLS: %', v_lista;
  end if;

  -- 2) nenhum privilegio direto em tabelas (unica excecao: SELECT em usuarios para authenticated)
  select string_agg(grantee || ':' || table_name || ':' || privilege_type, ', ') into v_lista
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated', 'PUBLIC')
     and not (grantee = 'authenticated' and table_name = 'usuarios' and privilege_type = 'SELECT');
  if v_lista is not null then
    raise exception 'Privilegios diretos indevidos: %', v_lista;
  end if;

  -- 3) usuarios: unica politica e leitura da propria linha
  if (select count(*) from pg_policy where polrelid = 'public.usuarios'::regclass) <> 1 then
    raise exception 'usuarios deveria ter exatamente 1 politica (leitura da propria linha)';
  end if;
  select string_agg(c.relname, ', ') into v_lista
    from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relnamespace = 'public'::regnamespace and c.relname <> 'usuarios';
  if v_lista is not null then
    raise exception 'Politicas inesperadas em: %', v_lista;
  end if;

  -- 4) funcoes de trigger nao executaveis por anon/authenticated
  select string_agg(p.oid::regprocedure::text, ', ') into v_lista
    from pg_proc p
   where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
     and p.prorettype = 'trigger'::regtype
     and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if v_lista is not null then
    raise exception 'Funcoes de trigger expostas: %', v_lista;
  end if;

  -- 5) sequence do codigo do pedido fechada
  if has_sequence_privilege('anon', 'public.seq_pedido_codigo', 'USAGE')
     or has_sequence_privilege('authenticated', 'public.seq_pedido_codigo', 'USAGE') then
    raise exception 'seq_pedido_codigo nao pode ser usada diretamente';
  end if;
end $$;

rollback;
