-- =============================================================================
-- GZ1 Ingresso - Testes: ingressos administrativos (listagem + detalhe)
-- Arquivo: supabase/tests/ingressos_admin.test.sql
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.listar_ingressos_admin(uuid, uuid, text, public.status_ingresso)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_ingressos_admin';
  end if;
  if has_function_privilege('anon', 'public.obter_ingresso_admin(uuid)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar obter_ingresso_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_e1 uuid; v_e2 uuid;
  v_r1 jsonb; v_r2 jsonb; v_pag jsonb;
  v_ped1 uuid; v_ped2 uuid; v_cod1 text; v_pedcod1 text;
  v_i1 uuid; v_i2 uuid; v_i3 uuid;
  v_lista jsonb; v_det jsonb; v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Ing', 'adming_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Ing', 'porting_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ing 1','ing1-'||replace(gen_random_uuid()::text,'-',''), now() + interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e1;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Ing 2','ing2-'||replace(gen_random_uuid()::text,'-',''), now() + interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e1,'Lote I1',1,100,40,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e2,'Lote I2',1,100,40,'MANUAL','ATIVO');

  v_r1 := public.criar_reserva(v_e1, 'Comprador Ing', '11999990010', 'ing@test.local', array['Participante Alfa','Participante Beta']);
  v_ped1 := (v_r1->>'pedido_id')::uuid; v_pedcod1 := v_r1->>'codigo_pedido';
  v_pag := public.criar_pagamento_pendente_por_token((v_r1->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-ing-1');

  select id into v_i1 from public.ingressos where pedido_id = v_ped1 order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id = v_ped1 order by codigo offset 1 limit 1;
  select codigo into v_cod1 from public.ingressos where id = v_i1;

  -- i2 utilizado + entrada real
  update public.ingressos set status = 'UTILIZADO', utilizado_em = now() where id = v_i2;
  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_i2, v_e1, v_admin, 'QR_CODE', now());

  v_r2 := public.criar_reserva(v_e2, 'Comprador Ing 2', '11999990011', 'ing2@test.local', array['Participante Gama']);
  v_ped2 := (v_r2->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r2->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-ing-2');
  select id into v_i3 from public.ingressos where pedido_id = v_ped2 order by codigo limit 1;

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.listar_ingressos_admin();
    raise exception 'B: PORTARIA nao deveria listar ingressos admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN permitido
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- D) filtro evento
  v_lista := public.listar_ingressos_admin(p_evento_id => v_e1);
  if jsonb_array_length(v_lista) <> 2 then raise exception 'D: evento1 deveria ter 2'; end if;

  -- E) filtro pedido
  v_lista := public.listar_ingressos_admin(p_pedido_id => v_ped1);
  if jsonb_array_length(v_lista) <> 2 then raise exception 'E: pedido1 deveria ter 2'; end if;

  -- F) filtro status
  v_lista := public.listar_ingressos_admin(p_evento_id => v_e1, p_status => 'UTILIZADO'::public.status_ingresso);
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'ingresso_id')::uuid <> v_i2 then
    raise exception 'F: filtro UTILIZADO incorreto';
  end if;

  -- G) busca por codigo do ingresso
  v_lista := public.listar_ingressos_admin(p_busca => v_cod1);
  if not exists (select 1 from jsonb_array_elements(v_lista) e where (e->>'ingresso_id')::uuid = v_i1) then
    raise exception 'G: busca por codigo falhou';
  end if;

  -- H) busca por participante
  v_lista := public.listar_ingressos_admin(p_evento_id => v_e1, p_busca => 'Beta');
  if jsonb_array_length(v_lista) <> 1 or (v_lista->0->>'ingresso_id')::uuid <> v_i2 then
    raise exception 'H: busca por participante falhou';
  end if;

  -- I) busca por codigo do pedido
  v_lista := public.listar_ingressos_admin(p_busca => v_pedcod1);
  if jsonb_array_length(v_lista) <> 2 then raise exception 'I: busca por pedido deveria achar 2'; end if;

  -- J) inexistente
  v_lista := public.listar_ingressos_admin(p_busca => 'zzz-nao-existe-zzz');
  if jsonb_array_length(v_lista) <> 0 then raise exception 'J: inexistente deveria ser vazio'; end if;

  -- N) sem qr_token
  v_lista := public.listar_ingressos_admin(p_evento_id => v_e1);
  if (v_lista->0 ? 'qr_token') or (v_lista->0 ? 'checkout_token') then
    raise exception 'N: campos sensiveis expostos';
  end if;

  -- K) UTILIZADO retorna utilizado_em
  v_lista := public.listar_ingressos_admin(p_evento_id => v_e1, p_status => 'UTILIZADO'::public.status_ingresso);
  if (v_lista->0->>'utilizado_em') is null then raise exception 'K: utilizado_em ausente'; end if;

  -- L) detalhe valido (com entrada)
  v_det := public.obter_ingresso_admin(v_i2);
  if (v_det->>'codigo') is distinct from (select codigo from public.ingressos where id = v_i2) then
    raise exception 'L: detalhe codigo incorreto';
  end if;
  if (v_det->'entrada'->>'entrada_id') is null then raise exception 'L: entrada ausente no detalhe'; end if;
  if (v_det ? 'qr_token') or (v_det ? 'checkout_token') then raise exception 'L: tokens expostos'; end if;

  -- M) detalhe inexistente
  if public.obter_ingresso_admin(gen_random_uuid()) is not null then
    raise exception 'M: inexistente deveria retornar null';
  end if;
end $$;

select 'ingressos_admin: todos os testes passaram' as resultado;

rollback;
