-- =============================================================================
-- GZ1 Ingresso - Testes: compartilhamento de ingresso individual
-- Arquivo: supabase/tests/compartilhamento_ingresso.test.sql
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.obter_qr_compartilhamento(text)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode acessar obter_qr_compartilhamento';
  end if;
  if not has_function_privilege('anon', 'public.obter_compartilhamento_ingresso(text)', 'EXECUTE') then
    raise exception 'ACL: anon deveria acessar obter_compartilhamento_ingresso';
  end if;
end $$;

do $$
declare
  v_e uuid; v_e2 uuid;
  v_r jsonb; v_r2 jsonb; v_bad jsonb;
  v_ped1 uuid; v_ped2 uuid; v_cod1 text;
  v_pag jsonb;
  v_i1 uuid; v_i2 uuid; v_ing_other uuid;
  v_sh1 jsonb; v_tok1 text;
  v_sh2 jsonb; v_tok2 text;
  v_rec jsonb; v_rec_token text;
  v_det jsonb; v_qr text; v_qr_real text;
  v_rand text;
begin
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Share','share-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Share 2','share2-'||replace(gen_random_uuid()::text,'-',''), now()+interval '3 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS') returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e,'Lote S',1,100,40,'MANUAL','ATIVO');
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values (v_e2,'Lote S2',1,100,40,'MANUAL','ATIVO');

  v_r := public.criar_reserva(v_e,'Comprador Share','11999990030','share@test.local',array['Share 1','Share 2']);
  v_ped1 := (v_r->>'pedido_id')::uuid; v_cod1 := v_r->>'codigo_pedido';
  v_pag := public.criar_pagamento_pendente_por_token((v_r->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-share-1');
  select id into v_i1 from public.ingressos where pedido_id=v_ped1 order by codigo limit 1;
  select id into v_i2 from public.ingressos where pedido_id=v_ped1 order by codigo offset 1 limit 1;

  -- outro pedido (evento 2) para teste "ingresso de outro pedido"
  v_r2 := public.criar_reserva(v_e2,'Comprador Share 2','11999990031',null,array['Outro']);
  v_ped2 := (v_r2->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_r2->>'checkout_token')::uuid,'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid,'tx-share-2');
  select id into v_ing_other from public.ingressos where pedido_id=v_ped2 order by codigo limit 1;

  -- recovery token do pedido 1
  v_rec := public.recuperar_ingressos(v_cod1, '11999990030');
  v_rec_token := v_rec->>'token';

  -- A) checkout + ingresso do pedido => ok
  v_sh1 := public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_i1);
  if (v_sh1->>'ok')::boolean is not true then raise exception 'A: deveria criar share'; end if;
  v_tok1 := v_sh1->>'token';

  -- B) recovery + ingresso do pedido => ok
  v_sh2 := public.criar_compartilhamento_ingresso(null, v_rec_token, v_i2);
  if (v_sh2->>'ok')::boolean is not true then raise exception 'B: recovery deveria criar share'; end if;
  v_tok2 := v_sh2->>'token';

  -- C) ingresso de outro pedido => negado
  v_bad := public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_ing_other);
  if (v_bad->>'ok')::boolean is not false then raise exception 'C: ingresso de outro pedido deveria ser negado'; end if;

  -- D) checkout invalido => negado
  v_bad := public.criar_compartilhamento_ingresso(gen_random_uuid(), null, v_i1);
  if (v_bad->>'ok')::boolean is not false then raise exception 'D: checkout invalido deveria ser negado'; end if;

  -- E) recovery invalido => negado
  v_bad := public.criar_compartilhamento_ingresso(null, 'recovery-invalido', v_i1);
  if (v_bad->>'ok')::boolean is not false then raise exception 'E: recovery invalido deveria ser negado'; end if;

  -- G/H/I) RESERVADO / CANCELADO / EXPIRADO => negado
  update public.ingressos set status='RESERVADO' where id=v_i1;
  v_bad := public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_i1);
  if (v_bad->>'ok')::boolean is not false then raise exception 'G: RESERVADO deveria ser negado'; end if;
  update public.ingressos set status='VALIDO' where id=v_i1;

  update public.ingressos set status='CANCELADO' where id=v_i1;
  v_bad := public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_i1);
  if (v_bad->>'ok')::boolean is not false then raise exception 'H: CANCELADO deveria ser negado'; end if;
  update public.ingressos set status='VALIDO' where id=v_i1;

  update public.ingressos set status='EXPIRADO' where id=v_i1;
  v_bad := public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_i1);
  if (v_bad->>'ok')::boolean is not false then raise exception 'I: EXPIRADO deveria ser negado'; end if;
  update public.ingressos set status='VALIDO' where id=v_i1;

  -- J) share valido => somente aquele ingresso + sem tokens sensiveis
  v_det := public.obter_compartilhamento_ingresso(v_tok1);
  if v_det is null then raise exception 'J: share deveria resolver'; end if;
  if (v_det->>'ingresso_id')::uuid <> v_i1 then raise exception 'J: ingresso errado'; end if;
  if (v_det->>'codigo') is distinct from (select codigo from public.ingressos where id=v_i1) then
    raise exception 'J: codigo divergente';
  end if;
  if (v_det ? 'qr_token') or (v_det ? 'checkout_token') or (v_det ? 'recovery_token') or (v_det ? 'comprador_nome') then
    raise exception 'M/N/O: dados sensiveis expostos no share publico';
  end if;

  -- K) token invalido => null
  v_rand := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  if public.obter_compartilhamento_ingresso(v_rand) is not null then
    raise exception 'K: token invalido deveria ser nulo';
  end if;

  -- L) revogacao: novo share do i1 revoga o token1
  perform public.criar_compartilhamento_ingresso((v_r->>'checkout_token')::uuid, null, v_i1);
  if public.obter_compartilhamento_ingresso(v_tok1) is not null then
    raise exception 'L: token revogado deveria ser nulo';
  end if;
  -- token2 (i2) permanece valido (independente)
  if public.obter_compartilhamento_ingresso(v_tok2) is null then
    raise exception 'L: token de outro ingresso nao deveria ser revogado';
  end if;

  -- QR token (service_role/owner): igual ao qr_token real do ingresso; status VALIDO
  select qr_token into v_qr_real from public.ingressos where id=v_i2;
  v_qr := public.obter_qr_compartilhamento(v_tok2);
  if v_qr is null or v_qr <> v_qr_real then
    raise exception 'QR: qr_token do share deveria ser o real do ingresso';
  end if;
end $$;

select 'compartilhamento_ingresso: todos os testes passaram' as resultado;

rollback;
