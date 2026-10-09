-- =============================================================================
-- GZ1 Ingresso - Testes: busca por nome e registro por nome (portaria)
-- Arquivo: supabase/tests/portaria_busca_nome.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
declare
  v_op uuid := gen_random_uuid();
  v_e1 uuid;
  v_e2 uuid;
  v_r1 jsonb;
  v_r2 jsonb;
  v_pag jsonb;
  v_ped1 uuid;
  v_i1 uuid;
  v_i2 uuid;
  v_outro uuid;
  v_e2_ing uuid;
  v_lista jsonb;
  v_res jsonb;
  v_res2 jsonb;
  v_n integer;
  v_entradas integer;
begin
  insert into auth.users (id) values (v_op);
  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_op, 'Operador Busca', 'opbusca_' || replace(v_op::text,'-','') || '@test.local', 'PORTARIA', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_op::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_op::text, true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Busca 1','busca1-'||replace(gen_random_uuid()::text,'-',''), now() + interval '1 hour','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e1;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Busca 2','busca2-'||replace(gen_random_uuid()::text,'-',''), now() + interval '1 hour','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e2;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e1,'Lote B1',1,100,1,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e2,'Lote B2',1,100,1,'MANUAL','ATIVO');

  -- E1: 3 ingressos (2 com o MESMO nome) via fluxo de dominio ----------------
  v_r1 := public.criar_reserva(v_e1, 'Comprador B', '11999990000', null, array['Teste Busca Nome E2E','Teste Busca Nome E2E','Outro Nome']);
  v_ped1 := (v_r1->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r1->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-busca-1');

  select id into v_i1 from public.ingressos where pedido_id = v_ped1 and participante_nome = 'Teste Busca Nome E2E' order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id = v_ped1 and participante_nome = 'Teste Busca Nome E2E' order by codigo offset 1 limit 1;
  select id into v_outro from public.ingressos where pedido_id = v_ped1 and participante_nome = 'Outro Nome';

  -- E2: 1 ingresso com o MESMO nome ------------------------------------------
  v_r2 := public.criar_reserva(v_e2, 'Comprador B2', '11999990001', null, array['Teste Busca Nome E2E']);
  v_pag := public.criar_pagamento_pendente_por_token((v_r2->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-busca-2');
  select id into v_e2_ing from public.ingressos where pedido_id = (v_r2->>'pedido_id')::uuid;

  -- Eventos passam a estar em andamento (fixture).
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour', vendas_status = 'ENCERRADAS'
   where id in (v_e1, v_e2);

  -- A/B) busca no evento correto retorna os 2 ingressos de mesmo nome ---------
  v_lista := public.buscar_ingressos_por_nome(v_e1, 'Teste Busca Nome E2E');
  v_n := jsonb_array_length(v_lista);
  if v_n <> 2 then
    raise exception 'A/B: esperado 2 ingressos, obtido %', v_n;
  end if;

  -- D) um deles tem status VALIDO --------------------------------------------
  if not exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'ingresso_id')::uuid = v_i1 and (e->>'status') = 'VALIDO') then
    raise exception 'D: ingresso VALIDO nao retornado';
  end if;

  -- C) nome inexistente => lista vazia ---------------------------------------
  if jsonb_array_length(public.buscar_ingressos_por_nome(v_e1, 'Nao Existe Esse Nome')) <> 0 then
    raise exception 'C: nome inexistente deveria retornar vazio';
  end if;

  -- H) ingresso de outro evento nao aparece e registro retorna EVENTO_INCORRETO
  if exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'ingresso_id')::uuid = v_e2_ing) then
    raise exception 'H: ingresso de outro evento apareceu na busca';
  end if;
  v_res := public.registrar_entrada_nome(v_e1, v_e2_ing);
  if (v_res->>'resultado') <> 'EVENTO_INCORRETO' then
    raise exception 'H: esperado EVENTO_INCORRETO, obtido %', v_res->>'resultado';
  end if;

  -- F) registrar entrada por nome => LIBERADO --------------------------------
  v_res := public.registrar_entrada_nome(v_e1, v_i1);
  if (v_res->>'resultado') <> 'LIBERADO' then
    raise exception 'F: esperado LIBERADO, obtido %', v_res->>'resultado';
  end if;
  if (select status from public.ingressos where id = v_i1) <> 'UTILIZADO' then
    raise exception 'F: ingresso deveria estar UTILIZADO';
  end if;

  -- E) busca volta com o ingresso UTILIZADO ----------------------------------
  v_lista := public.buscar_ingressos_por_nome(v_e1, 'Teste Busca Nome E2E');
  if not exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'ingresso_id')::uuid = v_i1 and (e->>'status') = 'UTILIZADO') then
    raise exception 'E: ingresso UTILIZADO nao retornado';
  end if;

  -- G) segunda chamada => JA_UTILIZADO e entrada unica -----------------------
  v_res2 := public.registrar_entrada_nome(v_e1, v_i1);
  if (v_res2->>'resultado') <> 'JA_UTILIZADO' then
    raise exception 'G: esperado JA_UTILIZADO, obtido %', v_res2->>'resultado';
  end if;
  select count(*) into v_entradas from public.entradas where ingresso_id = v_i1 and anulada_em is null;
  if v_entradas <> 1 then
    raise exception 'G: esperado 1 entrada ativa, encontrado %', v_entradas;
  end if;

  -- C) UTILIZADO retorna utilizado_em preenchido -----------------------------
  if not exists (
    select 1 from jsonb_array_elements(v_lista) e
     where (e->>'ingresso_id')::uuid = v_i1
       and (e->>'status') = 'UTILIZADO'
       and (e->>'utilizado_em') is not null
  ) then
    raise exception 'C: UTILIZADO deveria retornar utilizado_em';
  end if;

  -- T) match tolerante: outra ordem de palavras / sem acento ainda encontra
  v_lista := public.buscar_ingressos_por_nome(v_e1, 'E2E Nome Busca Teste');
  if jsonb_array_length(v_lista) <> 2 then
    raise exception 'T: match tolerante (ordem) deveria retornar 2, obtido %', jsonb_array_length(v_lista);
  end if;
  v_lista := public.buscar_ingressos_por_nome(v_e1, 'nome busca');
  if jsonb_array_length(v_lista) <> 2 then
    raise exception 'T: match tolerante (parcial) deveria retornar 2, obtido %', jsonb_array_length(v_lista);
  end if;

  -- F) CANCELADO continua aparecendo (sem filtro de status), com o status real
  update public.ingressos set status = 'CANCELADO' where id = v_e2_ing; -- nao afeta E1
  v_lista := public.buscar_ingressos_por_nome(v_e1, 'Outro Nome');
  if not exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'ingresso_id')::uuid = v_outro) then
    raise exception 'F: ingresso do evento deveria aparecer na busca';
  end if;

  -- I) sem operador => negado -------------------------------------------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.buscar_ingressos_por_nome(v_e1, 'Teste Busca Nome E2E');
    raise exception 'I: deveria negar busca sem operador';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'I: erro inesperado (busca): %', sqlerrm;
    end if;
  end;
  begin
    perform public.registrar_entrada_nome(v_e1, v_i2);
    raise exception 'I: deveria negar registro sem operador';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'I: erro inesperado (registro): %', sqlerrm;
    end if;
  end;
end $$;

select 'portaria_busca_nome: todos os testes passaram' as resultado;

rollback;
