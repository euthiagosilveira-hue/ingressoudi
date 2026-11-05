-- =============================================================================
-- Ingressoudi - Testes: cartao de credito (tentativas, forma de pagamento,
-- estorno/contestacao externos, liga/desliga por casa)
-- Arquivo: supabase/tests/cartao_credito.test.sql
-- =============================================================================

begin;

-- ACL: o fluxo do cartao so roda no servidor; o liga/desliga e do super admin.
do $$
begin
  if has_function_privilege('anon', 'public.iniciar_tentativa_cartao(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.iniciar_tentativa_cartao(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.registrar_tentativa_cartao(uuid,text,text,text,smallint,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.estornar_pedido_externo(uuid,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.definir_cartao_organizacao(uuid,boolean)', 'EXECUTE') then
    raise exception 'ACL: funcoes do cartao expostas';
  end if;
  if not has_function_privilege('service_role', 'public.iniciar_tentativa_cartao(uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.estornar_pedido_externo(uuid,text,text)', 'EXECUTE') then
    raise exception 'ACL: service_role precisa executar o fluxo do cartao';
  end if;
  if has_table_privilege('authenticated', 'public.pagamentos_cartao_tentativas', 'SELECT')
     or has_table_privilege('anon', 'public.pagamentos_cartao_tentativas', 'SELECT') then
    raise exception 'ACL: tentativas de cartao nao podem ser lidas pelo cliente';
  end if;
end $$;

do $$
declare
  v_org uuid; v_admin uuid := gen_random_uuid(); v_super uuid := gen_random_uuid();
  v_ev uuid; v_res jsonb; v_pag jsonb; v_t jsonb; v_r jsonb; v_back jsonb;
  v_token uuid; v_pedido uuid; v_pag_id uuid; i int;
begin
  insert into public.organizacoes (nome, slug) values ('Cartao A', 'ca-' || substr(md5(random()::text),1,10)) returning id into v_org;
  insert into auth.users (id) values (v_admin), (v_super);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Adm', 'ca_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_super, 'Super', 'cs_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id = v_admin;

  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Show Cartao', 'ca-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote', 1, 50, 10.00, 'MANUAL', 'ATIVO');

  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', 'c@test.local', array['Ana', 'Bia']);
  v_token := (v_res->>'checkout_token')::uuid;
  v_pedido := (v_res->>'pedido_id')::uuid;

  -- C1) sem pagamento iniciado: erro
  begin
    perform public.iniciar_tentativa_cartao(v_token);
    raise exception 'C1: deveria exigir pagamento iniciado';
  exception when others then
    if position('pagamento nao iniciado' in lower(sqlerrm)) = 0 then raise exception 'C1: %', sqlerrm; end if;
  end;

  v_pag := public.criar_pagamento_pendente_por_token(v_token, 'MERCADO_PAGO');
  v_pag_id := (v_pag->>'pagamento_id')::uuid;
  perform public.registrar_cobranca_externa(v_pag_id, 'MERCADO_PAGO', 'pix-1', 'pix-1', v_pag_id::text, 'copia', 'qr');

  -- C2) casa com cartao desligado: bloqueia
  begin
    perform public.iniciar_tentativa_cartao(v_token);
    raise exception 'C2: cartao desligado deveria bloquear';
  exception when others then
    if position('cartao nao liberado' in lower(sqlerrm)) = 0 then raise exception 'C2: %', sqlerrm; end if;
  end;

  -- C3) liga/desliga: so super admin
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.definir_cartao_organizacao(v_org, true);
    raise exception 'C3: admin comum nao pode ligar o cartao';
  exception when others then
    if position('super' in lower(sqlerrm)) = 0 then raise exception 'C3: %', sqlerrm; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  update public.organizacoes set cartao_ativo = true where id = v_org;

  -- C4) backend devolve dados do cartao
  v_back := public.obter_checkout_pagamento_backend(v_token);
  if (v_back->>'cartao_ativo')::boolean is not true or (v_back->>'tentativas_cartao')::int <> 0
     or v_back->>'evento_nome' <> 'Show Cartao' or v_back->>'comprador_nome' <> 'Comprador' then
    raise exception 'C4: backend sem dados do cartao: %', v_back;
  end if;

  -- C5) tentativa recusada e depois aprovada: pagamento vira CARTAO com detalhes
  v_t := public.iniciar_tentativa_cartao(v_token);
  if v_t->>'resultado' <> 'iniciada' or (v_t->>'numero')::int <> 1 then raise exception 'C5: %', v_t; end if;
  perform public.registrar_tentativa_cartao((v_t->>'tentativa_id')::uuid, 'card-1', 'RECUSADA', 'cc_rejected_other_reason', 1::smallint, 'master', '6351');
  v_t := public.iniciar_tentativa_cartao(v_token);
  if (v_t->>'numero')::int <> 2 then raise exception 'C5: numero da segunda tentativa: %', v_t; end if;
  perform public.registrar_tentativa_cartao((v_t->>'tentativa_id')::uuid, 'card-2', 'APROVADA', 'accredited', 3::smallint, 'visa', '1234');
  perform public.confirmar_pagamento(v_pag_id, 'card-2', v_pag_id::text);
  if (select row(forma_pagamento, parcelas, cartao_bandeira, cartao_final, transacao_id)::text
        from public.pagamentos where id = v_pag_id) <> '(CARTAO,3,visa,1234,card-2)' then
    raise exception 'C5: forma de pagamento: %', (select row(forma_pagamento, parcelas, cartao_bandeira, cartao_final, transacao_id)::text from public.pagamentos where id = v_pag_id);
  end if;
  if (select status from public.pedidos where id = v_pedido) <> 'PAGO' then raise exception 'C5: pedido deveria estar PAGO'; end if;

  -- C6) pagamento aprovado: nova tentativa responde ja_aprovado
  v_t := public.iniciar_tentativa_cartao(v_token);
  if v_t->>'resultado' <> 'ja_aprovado' then raise exception 'C6: %', v_t; end if;

  -- C7) estorno de outra transacao (o Pix cancelado) e ignorado
  v_r := public.estornar_pedido_externo(v_pag_id, 'pix-1', 'REEMBOLSO');
  if v_r->>'resultado' <> 'ignorado' then raise exception 'C7: %', v_r; end if;

  -- C8) contestacao da transacao aprovada: cancela pedido e ingressos nao usados
  update public.ingressos set status = 'UTILIZADO', utilizado_em = now()
   where id = (select id from public.ingressos where pedido_id = v_pedido order by id limit 1);
  v_r := public.estornar_pedido_externo(v_pag_id, 'card-2', 'CONTESTACAO');
  if v_r->>'resultado' <> 'cancelado' or (v_r->>'ingressos_cancelados')::int <> 1
     or (v_r->>'ingressos_utilizados')::int <> 1 then
    raise exception 'C8: %', v_r;
  end if;
  if (select status from public.pagamentos where id = v_pag_id) <> 'CANCELADO'
     or (select status from public.pedidos where id = v_pedido) <> 'CANCELADO' then
    raise exception 'C8: estados finais incorretos';
  end if;
  if not exists (select 1 from public.auditoria where entidade_id = v_pedido and acao = 'CONTESTACAO_RECEBIDA') then
    raise exception 'C8: auditoria ausente';
  end if;
  -- repetir e inofensivo
  v_r := public.estornar_pedido_externo(v_pag_id, 'card-2', 'CONTESTACAO');
  if v_r->>'resultado' <> 'ignorado' then raise exception 'C8: repeticao deveria ser ignorada'; end if;

  -- C9) limite de 5 tentativas
  v_res := public.criar_reserva(v_ev, 'Comprador 2', '11999990001', 'd@test.local', array['Caio']);
  v_token := (v_res->>'checkout_token')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token(v_token, 'MERCADO_PAGO');
  for i in 1..5 loop
    v_t := public.iniciar_tentativa_cartao(v_token);
  end loop;
  begin
    perform public.iniciar_tentativa_cartao(v_token);
    raise exception 'C9: sexta tentativa deveria bloquear';
  exception when others then
    if position('limite' in lower(sqlerrm)) = 0 then raise exception 'C9: %', sqlerrm; end if;
  end;

  -- C10) Pix aprovado continua PIX; reembolso externo cancela
  v_res := public.criar_reserva(v_ev, 'Comprador 3', '11999990002', 'e@test.local', array['Duda']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'pix-9', null);
  if (select forma_pagamento from public.pagamentos where id = (v_pag->>'pagamento_id')::uuid) <> 'PIX' then
    raise exception 'C10: Pix deveria ficar PIX';
  end if;
  v_r := public.estornar_pedido_externo((v_pag->>'pagamento_id')::uuid, 'pix-9', 'REEMBOLSO');
  if v_r->>'resultado' <> 'cancelado'
     or (select status from public.pagamentos where id = (v_pag->>'pagamento_id')::uuid) <> 'REEMBOLSADO' then
    raise exception 'C10: reembolso externo: %', v_r;
  end if;

  -- C11) reserva vencida nao inicia cartao
  v_res := public.criar_reserva(v_ev, 'Comprador 4', '11999990003', 'f@test.local', array['Eva']);
  perform public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  update public.pedidos set reserva_expira_em = now() - interval '1 minute' where id = (v_res->>'pedido_id')::uuid;
  begin
    perform public.iniciar_tentativa_cartao((v_res->>'checkout_token')::uuid);
    raise exception 'C11: reserva vencida deveria bloquear';
  exception when others then
    if position('expirada' in lower(sqlerrm)) = 0 then raise exception 'C11: %', sqlerrm; end if;
  end;
end $$;

rollback;
