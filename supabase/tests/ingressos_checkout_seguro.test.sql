-- =============================================================================
-- GZ1 Ingresso - Testes: ingressos do checkout (pos-pagamento)
-- Arquivo: supabase/tests/ingressos_checkout_seguro.test.sql
-- Executar como owner/service_role. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
declare
  v_evento_id uuid;
  v_lote_id uuid;
  v_ra jsonb;
  v_rb jsonb;
  v_token_a uuid;
  v_token_b uuid;
  v_pedido_b uuid;
  v_pag jsonb;
  v_resp jsonb;
  v_item jsonb;
  v_ing_id uuid;
  v_db_qr text;
  v_count integer;
  v_todos_qr boolean;
begin
  -- fixture ------------------------------------------------------------------
  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Ingressos Checkout', 'teste-ingressos-' || replace(gen_random_uuid()::text, '-', ''),
    now() + interval '20 days', 'Local I', 'End I',
    200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento_id;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento_id, 'Lote I', 1, 100, 40, 'MANUAL', 'ATIVO')
  returning id into v_lote_id;

  -- A) token invalido/inexistente => null ------------------------------------
  if public.obter_ingressos_checkout(gen_random_uuid()) is not null then
    raise exception 'A: token inexistente deveria retornar null';
  end if;
  if public.obter_ingressos_checkout(null) is not null then
    raise exception 'A: token null deveria retornar null';
  end if;

  -- B) pedido RESERVADO (sem pagamento) => indisponivel, sem ingressos -------
  v_ra := public.criar_reserva(v_evento_id, 'Comprador A', '34999999990', null, array['A1', 'A2']);
  v_token_a := (v_ra->>'checkout_token')::uuid;
  v_resp := public.obter_ingressos_checkout(v_token_a);
  if v_resp is null then
    raise exception 'B: resposta inesperadamente nula';
  end if;
  if (v_resp->>'disponivel')::boolean then
    raise exception 'B: pedido RESERVADO nao pode estar disponivel';
  end if;
  if jsonb_array_length(v_resp->'ingressos') <> 0 then
    raise exception 'B: pedido RESERVADO nao pode retornar ingressos';
  end if;

  -- C) pagamento PENDENTE => sem ingressos -----------------------------------
  v_rb := public.criar_reserva(v_evento_id, 'Comprador B', '34999999991', null, array['B1', 'B2']);
  v_token_b := (v_rb->>'checkout_token')::uuid;
  v_pedido_b := (v_rb->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token(v_token_b, 'MERCADO_PAGO');
  if (v_pag->>'status') <> 'PENDENTE' then
    raise exception 'C: pagamento deveria estar PENDENTE';
  end if;
  v_resp := public.obter_ingressos_checkout(v_token_b);
  if (v_resp->>'disponivel')::boolean then
    raise exception 'C: pagamento PENDENTE nao pode liberar ingressos';
  end if;
  if jsonb_array_length(v_resp->'ingressos') <> 0 then
    raise exception 'C: pagamento PENDENTE nao pode retornar ingressos';
  end if;

  -- D) pagamento APROVADO + pedido PAGO => ingressos retornados --------------
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-teste-1');
  if (select status from public.pedidos where id = v_pedido_b) <> 'PAGO' then
    raise exception 'D: pedido deveria estar PAGO apos confirmacao';
  end if;

  v_resp := public.obter_ingressos_checkout(v_token_b);
  if not (v_resp->>'disponivel')::boolean then
    raise exception 'D: pedido PAGO/APROVADO deveria estar disponivel';
  end if;
  if jsonb_array_length(v_resp->'ingressos') <> 2 then
    raise exception 'D: esperado 2 ingressos, obtido %', jsonb_array_length(v_resp->'ingressos');
  end if;
  if (v_resp->>'codigo_pedido') <> (v_rb->>'codigo_pedido') then
    raise exception 'D: codigo_pedido divergente';
  end if;

  -- E) cada ingresso tem qr_token correto (igual ao banco) -------------------
  v_todos_qr := true;
  for v_item in select * from jsonb_array_elements(v_resp->'ingressos')
  loop
    v_ing_id := (v_item->>'ingresso_id')::uuid;
    select qr_token into v_db_qr from public.ingressos where id = v_ing_id;
    if v_item->'qr_token' is null or v_item->>'qr_token' is distinct from v_db_qr then
      v_todos_qr := false;
    end if;
    if (v_item->>'status') <> 'VALIDO' then
      raise exception 'E: ingresso recem-pago deveria estar VALIDO (%)', v_item->>'status';
    end if;
  end loop;
  if not v_todos_qr then
    raise exception 'E: qr_token ausente/divergente em algum ingresso';
  end if;

  -- F) ingresso UTILIZADO continua visivel, com status UTILIZADO -------------
  select id into v_ing_id
    from public.ingressos
   where pedido_id = v_pedido_b
   order by codigo
   limit 1;
  update public.ingressos
     set status = 'UTILIZADO', utilizado_em = now()
   where id = v_ing_id;

  v_resp := public.obter_ingressos_checkout(v_token_b);
  select * into v_item
    from jsonb_array_elements(v_resp->'ingressos') as e
   where (e->>'ingresso_id')::uuid = v_ing_id;
  if v_item is null then
    raise exception 'F: ingresso UTILIZADO deveria continuar visivel';
  end if;
  if (v_item->>'status') <> 'UTILIZADO' then
    raise exception 'F: status esperado UTILIZADO, obtido %', v_item->>'status';
  end if;
  if v_item->'qr_token' is null then
    raise exception 'F: ingresso UTILIZADO deveria manter o qr_token';
  end if;

  -- G) ingresso CANCELADO/EXPIRADO => sem QR utilizavel ----------------------
  select id into v_ing_id
    from public.ingressos
   where pedido_id = v_pedido_b
   order by codigo
   limit 1 offset 1;
  update public.ingressos set status = 'CANCELADO' where id = v_ing_id;

  v_resp := public.obter_ingressos_checkout(v_token_b);
  select * into v_item
    from jsonb_array_elements(v_resp->'ingressos') as e
   where (e->>'ingresso_id')::uuid = v_ing_id;
  if v_item is null then
    raise exception 'G: ingresso CANCELADO deveria ter estado informativo';
  end if;
  if (v_item->>'status') <> 'CANCELADO' then
    raise exception 'G: status esperado CANCELADO, obtido %', v_item->>'status';
  end if;
  if v_item->'qr_token' <> 'null'::jsonb then
    raise exception 'G: ingresso CANCELADO nao pode expor qr_token';
  end if;

  -- G2) ingresso EXPIRADO nao e retornado ------------------------------------
  select id into v_ing_id
    from public.ingressos
   where pedido_id = v_pedido_b
   order by codigo
   limit 1;
  update public.ingressos set status = 'EXPIRADO' where id = v_ing_id;

  v_resp := public.obter_ingressos_checkout(v_token_b);
  v_count := 0;
  for v_item in select * from jsonb_array_elements(v_resp->'ingressos')
  loop
    if (v_item->>'ingresso_id')::uuid = v_ing_id then
      v_count := v_count + 1;
    end if;
  end loop;
  if v_count <> 0 then
    raise exception 'G2: ingresso EXPIRADO nao deveria ser retornado';
  end if;

  -- H) privacidade: sem PII / sem checkout_token no topo ---------------------
  if (v_resp ? 'comprador_email')
     or (v_resp ? 'comprador_telefone')
     or (v_resp ? 'checkout_token')
     or (v_resp ? 'qr_token') then
    raise exception 'H: campos sensiveis expostos no retorno';
  end if;
end $$;

-- ACL ------------------------------------------------------------------------
do $$
begin
  -- anon pode ler os proprios ingressos via token
  if not has_function_privilege('anon', 'public.obter_ingressos_checkout(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon deveria executar obter_ingressos_checkout';
  end if;
  if not has_function_privilege('authenticated', 'public.obter_ingressos_checkout(uuid)', 'EXECUTE') then
    raise exception 'ACL: authenticated deveria executar obter_ingressos_checkout';
  end if;

  -- wrapper publico e SECURITY INVOKER (nunca DEFINER em public)
  if (select prosecdef from pg_proc where oid = 'public.obter_ingressos_checkout(uuid)'::regprocedure) then
    raise exception 'ACL: wrapper publico nao pode ser SECURITY DEFINER';
  end if;
  if not (select prosecdef from pg_proc where oid = 'private.obter_ingressos_checkout(uuid)'::regprocedure) then
    raise exception 'ACL: funcao privada deve ser SECURITY DEFINER';
  end if;

  -- RLS / acesso direto permanece fechado
  if has_table_privilege('anon', 'public.ingressos', 'SELECT') then
    raise exception 'ACL: anon nao pode ler ingressos diretamente';
  end if;
  if has_table_privilege('authenticated', 'public.pedidos', 'SELECT') then
    raise exception 'ACL: authenticated nao pode ler pedidos diretamente';
  end if;
end $$;

select 'ingressos_checkout_seguro: todos os testes passaram' as resultado;

rollback;
