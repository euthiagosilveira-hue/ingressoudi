-- =============================================================================
-- GZ1 Ingresso - Testes: registrar_entrada_qr (portaria atomica)
-- Arquivo: supabase/tests/portaria_registrar_entrada_qr.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
--
-- Simula operador autenticado via request.jwt.claims (auth.uid()), sem trocar
-- de role: a RPC valida auth.uid() + perfil (ADMINISTRADOR/PORTARIA).
-- =============================================================================

begin;

do $$
declare
  v_op uuid := gen_random_uuid();
  v_evento uuid;
  v_evento2 uuid;
  v_lote uuid;
  v_r jsonb;
  v_token text;
  v_pedido uuid;
  v_pag jsonb;
  v_res jsonb;
  v_res2 jsonb;
  v_entradas integer;
  v_r2 jsonb;
  v_token_canc text;
  v_r3 jsonb;
  v_token3 text;
begin
  -- operador de portaria ------------------------------------------------------
  insert into auth.users (id) values (v_op);
  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_op, 'Operador Teste', 'op_' || replace(v_op::text,'-','') || '@test.local', 'PORTARIA', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_op::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_op::text, true);

  -- fixtures ------------------------------------------------------------------
  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Portaria', 'teste-portaria-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '2 days', 'Local P', 'End P',
    200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento;

  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Teste Portaria 2', 'teste-portaria2-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '2 days', 'Local P2', 'End P2',
    200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento2;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento, 'Lote P', 1, 100, 40, 'MANUAL', 'ATIVO') returning id into v_lote;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_evento2, 'Lote P2', 1, 100, 40, 'MANUAL', 'ATIVO');

  -- Criar TODAS as reservas/pagamentos enquanto o evento ainda aceita reserva.
  -- A) ingresso VALIDO (evento 1)
  v_r := public.criar_reserva(v_evento, 'Comprador P', '34999999900', null, array['P1']);
  v_pedido := (v_r->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-portaria-1');
  select qr_token into v_token from public.ingressos where pedido_id = v_pedido order by codigo limit 1;

  -- E) ingresso CANCELADO (evento 1)
  v_r2 := public.criar_reserva(v_evento, 'Comprador P2', '34999999902', null, array['P2']);
  v_pag := public.criar_pagamento_pendente_por_token((v_r2->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-portaria-2');
  select qr_token into v_token_canc from public.ingressos where pedido_id = (v_r2->>'pedido_id')::uuid order by codigo limit 1;

  -- D) ingresso VALIDO de outro evento (evento 1)
  v_r3 := public.criar_reserva(v_evento, 'Comprador P3', '34999999903', null, array['P3']);
  v_pag := public.criar_pagamento_pendente_por_token((v_r3->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-portaria-3');
  select qr_token into v_token3 from public.ingressos where pedido_id = (v_r3->>'pedido_id')::uuid order by codigo limit 1;

  -- Agora os eventos passam a estar em andamento.
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour'
   where id in (v_evento, v_evento2);

  -- A) ingresso VALIDO => LIBERADO e UTILIZADO --------------------------------
  v_res := public.registrar_entrada_qr(v_evento, v_token);
  if (v_res->>'resultado') <> 'LIBERADO' then
    raise exception 'A: esperado LIBERADO, obtido %', v_res->>'resultado';
  end if;
  if (select status from public.ingressos where qr_token = v_token) <> 'UTILIZADO' then
    raise exception 'A: ingresso deveria estar UTILIZADO';
  end if;

  -- B) segunda leitura => JA_UTILIZADO e entrada unica ------------------------
  v_res2 := public.registrar_entrada_qr(v_evento, v_token);
  if (v_res2->>'resultado') <> 'JA_UTILIZADO' then
    raise exception 'B: esperado JA_UTILIZADO, obtido %', v_res2->>'resultado';
  end if;
  select count(*) into v_entradas from public.entradas e
    join public.ingressos i on i.id = e.ingresso_id
   where i.qr_token = v_token and e.anulada_em is null;
  if v_entradas <> 1 then
    raise exception 'B: esperado 1 entrada ativa, encontrado %', v_entradas;
  end if;

  -- C) QR inexistente => NAO_ENCONTRADO ---------------------------------------
  v_res := public.registrar_entrada_qr(v_evento, 'token-inexistente-' || replace(gen_random_uuid()::text,'-',''));
  if (v_res->>'resultado') <> 'NAO_ENCONTRADO' then
    raise exception 'C: esperado NAO_ENCONTRADO, obtido %', v_res->>'resultado';
  end if;

  -- D) evento incorreto => EVENTO_INCORRETO -----------------------------------
  v_res := public.registrar_entrada_qr(v_evento2, v_token3);
  if (v_res->>'resultado') <> 'EVENTO_INCORRETO' then
    raise exception 'D: esperado EVENTO_INCORRETO, obtido %', v_res->>'resultado';
  end if;

  -- E) ingresso CANCELADO => CANCELADO ----------------------------------------
  update public.ingressos set status = 'CANCELADO' where qr_token = v_token_canc;
  v_res := public.registrar_entrada_qr(v_evento, v_token_canc);
  if (v_res->>'resultado') <> 'CANCELADO' then
    raise exception 'E: esperado CANCELADO, obtido %', v_res->>'resultado';
  end if;

  -- F) acesso nao autenticado => erro controlado ------------------------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.registrar_entrada_qr(v_evento, v_token3);
    raise exception 'F: deveria negar sem operador autenticado';
  exception
    when others then
      if position('permiss' in lower(sqlerrm)) = 0 then
        raise exception 'F: erro inesperado: %', sqlerrm;
      end if;
  end;
end $$;

select 'portaria_registrar_entrada_qr: todos os testes passaram' as resultado;

rollback;
