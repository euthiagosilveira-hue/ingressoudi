-- =============================================================================
-- Ingressoudi - Testes: guarda de seguranca (RLS e permissoes)
-- Arquivo: supabase/tests/seguranca_acl.test.sql
-- Falha se alguma tabela ficar sem RLS, se anon/authenticated ganharem acesso
-- direto a tabelas, se surgir politica/SECURITY DEFINER no public, funcao sem
-- search_path fixo, listagem publica do storage ou funcao de trigger exposta.
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

  -- 2) nenhum privilegio direto em tabelas para anon/authenticated
  select string_agg(grantee || ':' || table_name || ':' || privilege_type, ', ') into v_lista
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated', 'PUBLIC');
  if v_lista is not null then
    raise exception 'Privilegios diretos indevidos: %', v_lista;
  end if;

  -- 3) nenhuma politica no schema public (acesso somente por RPC)
  select string_agg(c.relname || '.' || p.polname, ', ') into v_lista
    from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relnamespace = 'public'::regnamespace;
  if v_lista is not null then
    raise exception 'Politicas inesperadas: %', v_lista;
  end if;

  -- 3b) nenhuma funcao SECURITY DEFINER no schema public (exposto pela API)
  select string_agg(p.oid::regprocedure::text, ', ') into v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef;
  if v_lista is not null then
    raise exception 'SECURITY DEFINER no schema public: %', v_lista;
  end if;

  -- 3c) funcoes do public com search_path fixo
  select string_agg(p.oid::regprocedure::text, ', ') into v_lista
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prokind = 'f'
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  if v_lista is not null then
    raise exception 'Funcoes sem search_path fixo: %', v_lista;
  end if;

  -- 3d) bucket de capas sem listagem publica
  if exists (select 1 from pg_policy p
              where p.polrelid = 'storage.objects'::regclass
                and p.polcmd in ('r', '*')
                and (p.polroles = '{0}'::oid[] or 'anon'::regrole::oid = any(p.polroles))) then
    raise exception 'storage.objects com leitura/listagem para anon/public';
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
