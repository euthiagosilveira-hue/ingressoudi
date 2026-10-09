-- =============================================================================
-- GZ1 Ingresso - Testes: pagamentos multi-provedor
-- Arquivo: supabase/tests/pagamentos_multi_provedor.test.sql
--
-- Execucao: rodar como owner/service_role (ex.: SQL Editor ou supabase db).
-- Roda dentro de uma transacao e faz ROLLBACK ao final (nao persiste nada).
-- Falha levantando EXCEPTION com mensagem 'T#:' quando uma verificacao quebra.
-- =============================================================================

begin;

-- T1) Enum aceita STONE e MERCADO_PAGO ----------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'public' and t.typname = 'provedor_pagamento'
       and e.enumlabel = 'STONE'
  ) then
    raise exception 'T1: enum provedor_pagamento sem STONE';
  end if;

  if not exists (
    select 1 from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'public' and t.typname = 'provedor_pagamento'
       and e.enumlabel = 'MERCADO_PAGO'
  ) then
    raise exception 'T1: enum provedor_pagamento sem MERCADO_PAGO';
  end if;
end $$;

-- T2) Colunas neutras existem e sao nullable ----------------------------------
do $$
declare
  v_ok integer;
begin
  select count(*) into v_ok
    from information_schema.columns
   where table_schema = 'public' and table_name = 'pagamentos'
     and column_name in ('transacao_id', 'cobranca_id', 'referencia_externa')
     and is_nullable = 'YES';

  if v_ok <> 3 then
    raise exception 'T2: colunas neutras ausentes ou NOT NULL (encontradas %/3)', v_ok;
  end if;
end $$;

-- T3) Colunas legadas removidas -----------------------------------------------
do $$
declare
  v_legado integer;
begin
  select count(*) into v_legado
    from information_schema.columns
   where table_schema = 'public' and table_name = 'pagamentos'
     and column_name in ('mercado_pago_payment_id', 'mercado_pago_external_reference');

  if v_legado <> 0 then
    raise exception 'T3: colunas legadas do Mercado Pago ainda existem (%)', v_legado;
  end if;
end $$;

-- T4) Default do provedor e STONE ---------------------------------------------
do $$
declare
  v_default text;
begin
  select column_default into v_default
    from information_schema.columns
   where table_schema = 'public' and table_name = 'pagamentos'
     and column_name = 'provedor';

  if v_default is null or position('STONE' in v_default) = 0 then
    raise exception 'T4: default do provedor nao e STONE (atual=%)', coalesce(v_default, 'null');
  end if;
end $$;

-- T5) Signatures das RPCs -----------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'criar_pagamento_pendente' and p.pronargs = 5
  ) then
    raise exception 'T5: private.criar_pagamento_pendente(5 args) ausente';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'criar_pagamento_pendente' and p.pronargs = 5
  ) then
    raise exception 'T5: public.criar_pagamento_pendente(5 args) ausente';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'confirmar_pagamento' and p.pronargs = 3
  ) then
    raise exception 'T5: private.confirmar_pagamento(3 args) ausente';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'confirmar_pagamento' and p.pronargs = 3
  ) then
    raise exception 'T5: public.confirmar_pagamento(3 args) ausente';
  end if;
end $$;

-- T6) Unicidade parcial (provedor, transacao_id) ------------------------------
do $$
declare
  v_def text;
begin
  select indexdef into v_def
    from pg_indexes
   where schemaname = 'public' and indexname = 'uq_pagamentos_provedor_transacao';

  if v_def is null then
    raise exception 'T6: indice unico uq_pagamentos_provedor_transacao ausente';
  end if;
  if position('transacao_id' in v_def) = 0 or position('provedor' in v_def) = 0 then
    raise exception 'T6: indice unico nao cobre (provedor, transacao_id): %', v_def;
  end if;
  if position('IS NOT NULL' in upper(v_def)) = 0 then
    raise exception 'T6: indice unico sem clausula parcial WHERE transacao_id IS NOT NULL';
  end if;
end $$;

-- T7) Um pagamento por pedido (unique preservado) -----------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'uq_pagamentos_pedido' and conrelid = 'public.pagamentos'::regclass
  ) then
    raise exception 'T7: constraint uq_pagamentos_pedido ausente';
  end if;
end $$;

-- T8) Indices neutros ---------------------------------------------------------
do $$
declare
  v_ok integer;
begin
  select count(*) into v_ok
    from pg_indexes
   where schemaname = 'public'
     and indexname in ('idx_pagamentos_provedor', 'idx_pagamentos_referencia_externa');

  if v_ok <> 2 then
    raise exception 'T8: indices neutros ausentes (%/2)', v_ok;
  end if;
end $$;

-- T9) RPC criar_pagamento_pendente: pedido inexistente ------------------------
do $$
begin
  begin
    perform public.criar_pagamento_pendente(
      '00000000-0000-0000-0000-000000000000'::uuid,
      'STONE'::public.provedor_pagamento
    );
    raise exception 'T9: deveria falhar para pedido inexistente';
  exception
    when others then
      if position('Pedido' in sqlerrm) = 0 then
        raise exception 'T9: erro inesperado: %', sqlerrm;
      end if;
  end;
end $$;

-- T10) Provider invalido (fora do enum) deve falhar ---------------------------
do $$
begin
  begin
    perform public.criar_pagamento_pendente(
      '00000000-0000-0000-0000-000000000000'::uuid,
      'PIX'::public.provedor_pagamento
    );
    raise exception 'T10: provider invalido aceito';
  exception
    when invalid_text_representation then
      null; -- esperado: enum rejeita
  end;
end $$;

-- T11) RPC confirmar_pagamento: pagamento inexistente -------------------------
do $$
begin
  begin
    perform public.confirmar_pagamento('00000000-0000-0000-0000-000000000000'::uuid);
    raise exception 'T11: deveria falhar para pagamento inexistente';
  exception
    when others then
      if position('Pagamento' in sqlerrm) = 0 then
        raise exception 'T11: erro inesperado: %', sqlerrm;
      end if;
  end;
end $$;

-- T12) ACL: checkout publico x callback de sistema ----------------------------
do $$
begin
  -- Checkout publico agora e por token (criar_pagamento_pendente por pedido foi fechada).
  if not has_function_privilege(
    'anon',
    'public.criar_pagamento_pendente_por_token(uuid, public.provedor_pagamento, text, text, text)',
    'EXECUTE'
  ) then
    raise exception 'T12: anon deveria poder criar pagamento pendente por token (checkout)';
  end if;

  if has_function_privilege(
    'anon',
    'public.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)',
    'EXECUTE'
  ) then
    raise exception 'T12: anon NAO pode executar criar_pagamento_pendente(pedido_id)';
  end if;

  if has_function_privilege(
    'anon',
    'public.confirmar_pagamento(uuid, text, text)',
    'EXECUTE'
  ) then
    raise exception 'T12: anon NAO pode confirmar pagamento';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.confirmar_pagamento(uuid, text, text)',
    'EXECUTE'
  ) then
    raise exception 'T12: authenticated NAO pode confirmar pagamento';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.confirmar_pagamento(uuid, text, text)',
    'EXECUTE'
  ) then
    raise exception 'T12: service_role deveria poder confirmar pagamento';
  end if;
end $$;

-- T13) Acesso direto a tabela bloqueado + RLS habilitada ----------------------
do $$
begin
  if has_table_privilege('anon', 'public.pagamentos', 'SELECT') then
    raise exception 'T13: anon nao pode ler pagamentos diretamente';
  end if;

  if has_table_privilege('authenticated', 'public.pagamentos', 'UPDATE') then
    raise exception 'T13: authenticated nao pode escrever pagamentos diretamente';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.pagamentos'::regclass) then
    raise exception 'T13: RLS desabilitada em public.pagamentos';
  end if;
end $$;

-- T14) Nenhuma funcao SECURITY DEFINER em public ------------------------------
do $$
declare
  v_definer integer;
begin
  select count(*) into v_definer
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef = true;

  if v_definer <> 0 then
    raise exception 'T14: % funcao(oes) SECURITY DEFINER em public', v_definer;
  end if;
end $$;

select 'pagamentos_multi_provedor: todos os testes passaram' as resultado;

rollback;
