-- =============================================================================
-- Ingressoudi - Testes: reembolso de pedidos (preparar/concluir, service_role)
-- Arquivo: supabase/tests/reembolso_pedidos.test.sql
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.preparar_reembolso_pedido(uuid,uuid,uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.preparar_reembolso_pedido(uuid,uuid,uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.concluir_reembolso_pedido(uuid,uuid,boolean,text,text)', 'EXECUTE') then
    raise exception 'ACL: reembolso so pode ser chamado pelo servidor (service_role)';
  end if;
  if not has_function_privilege('service_role', 'public.preparar_reembolso_pedido(uuid,uuid,uuid,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.concluir_reembolso_pedido(uuid,uuid,boolean,text,text)', 'EXECUTE') then
    raise exception 'ACL: service_role precisa executar o reembolso';
  end if;
  if public.slug_organizacao_disponivel('reembolso') then
    raise exception 'Slug: reembolso deve ser reservado (rota publica)';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_admin uuid := gen_random_uuid();
  v_ev uuid; v_lote uuid; v_res jsonb; v_pag jsonb; v_op jsonb; v_op2 jsonb; v_fim jsonb;
  v_pedido uuid; v_pedido2 uuid; v_pedido3 uuid; v_ing uuid;
begin
  insert into public.organizacoes (nome, slug) values ('Reemb A', 're-a-' || substr(md5(random()::text),1,10)) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Reemb B', 're-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into auth.users (id) values (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Adm', 're_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id = v_admin;

  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Show Reembolso', 're-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote', 1, 50, 10.00, 'MANUAL', 'ATIVO') returning id into v_lote;

  -- pedido online pago (2 ingressos)
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana', 'Bia']);
  v_pedido := (v_res->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'mp-123', null);

  -- T1) outra organizacao nao prepara
  begin
    perform public.preparar_reembolso_pedido(v_pedido, v_org_b, v_admin, 'teste');
    raise exception 'T1: outra organizacao nao deveria reembolsar';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  -- T2) motivo obrigatorio
  begin
    perform public.preparar_reembolso_pedido(v_pedido, v_org, v_admin, '  ');
    raise exception 'T2: motivo vazio';
  exception when others then
    if position('motivo' in lower(sqlerrm)) = 0 then raise exception 'T2: %', sqlerrm; end if;
  end;

  -- T3) prepara: operacao pendente com valor total e transacao do MP; idempotente
  v_op := public.preparar_reembolso_pedido(v_pedido, v_org, v_admin, 'Desistencia no prazo');
  if v_op->>'provedor' <> 'MERCADO_PAGO' or v_op->>'transacao_id' <> 'mp-123'
     or (v_op->>'valor')::numeric <> (select valor_total from public.pedidos where id = v_pedido) then
    raise exception 'T3: preparo incorreto: %', v_op;
  end if;
  v_op2 := public.preparar_reembolso_pedido(v_pedido, v_org, v_admin, 'Outro motivo');
  if v_op2->>'operacao_id' <> v_op->>'operacao_id' then
    raise exception 'T3: deveria reaproveitar a operacao pendente';
  end if;

  -- T4) falha no provedor: pedido continua PAGO, operacao FALHOU, nova tentativa cria outra
  v_fim := public.concluir_reembolso_pedido((v_op->>'operacao_id')::uuid, v_org, false, null, 'saldo insuficiente');
  if v_fim->>'status' <> 'FALHOU' or (select status from public.pedidos where id = v_pedido) <> 'PAGO' then
    raise exception 'T4: falha deveria manter o pedido: %', v_fim;
  end if;
  v_op2 := public.preparar_reembolso_pedido(v_pedido, v_org, v_admin, 'Nova tentativa');
  if v_op2->>'operacao_id' = v_op->>'operacao_id' then
    raise exception 'T4: apos falha deveria criar nova operacao';
  end if;

  -- T5) sucesso: pagamento REEMBOLSADO, pedido CANCELADO, ingressos CANCELADO
  v_fim := public.concluir_reembolso_pedido((v_op2->>'operacao_id')::uuid, v_org, true, 'refund-999', null);
  if v_fim->>'status' <> 'CONCLUIDO' or (v_fim->>'ingressos_cancelados')::int <> 2 then
    raise exception 'T5: conclusao: %', v_fim;
  end if;
  if (select status from public.pedidos where id = v_pedido) <> 'CANCELADO'
     or (select status from public.pagamentos where id = (v_pag->>'pagamento_id')::uuid) <> 'REEMBOLSADO'
     or (select valor_reembolsado from public.pagamentos where id = (v_pag->>'pagamento_id')::uuid)
        <> (select valor from public.pagamentos where id = (v_pag->>'pagamento_id')::uuid)
     or exists (select 1 from public.ingressos where pedido_id = v_pedido and status <> 'CANCELADO') then
    raise exception 'T5: estados finais incorretos';
  end if;
  if (select reembolso_externo_id from public.cancelamentos_reembolsos where id = (v_op2->>'operacao_id')::uuid) <> 'refund-999' then
    raise exception 'T5: id externo nao gravado';
  end if;
  -- concluir de novo e inofensivo
  v_fim := public.concluir_reembolso_pedido((v_op2->>'operacao_id')::uuid, v_org, true, 'refund-999', null);
  if (v_fim->>'ja_processada')::boolean is not true then raise exception 'T5: deveria ser idempotente'; end if;

  -- T6) pedido ja reembolsado nao reembolsa de novo
  begin
    perform public.preparar_reembolso_pedido(v_pedido, v_org, v_admin, 'de novo');
    raise exception 'T6: pedido cancelado';
  exception when others then
    if position('pago' in lower(sqlerrm)) = 0 then raise exception 'T6: %', sqlerrm; end if;
  end;

  -- T7) ingresso ja utilizado bloqueia
  v_res := public.criar_reserva(v_ev, 'Comprador 2', '11999990001', null, array['Caio']);
  v_pedido2 := (v_res->>'pedido_id')::uuid;
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'mp-124', null);
  update public.ingressos set status = 'UTILIZADO', utilizado_em = now() where pedido_id = v_pedido2;
  begin
    perform public.preparar_reembolso_pedido(v_pedido2, v_org, v_admin, 'entrou');
    raise exception 'T7: ingresso utilizado';
  exception when others then
    if position('utilizado' in lower(sqlerrm)) = 0 then raise exception 'T7: %', sqlerrm; end if;
  end;

  -- T8) venda em dinheiro: provedor DINHEIRO (servidor nao chama o Mercado Pago)
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.criar_venda_manual_admin(v_ev, v_lote, 'Porta', '11999990002', array['Duda']);
  v_pedido3 := (v_res->>'pedido_id')::uuid;
  v_op := public.preparar_reembolso_pedido(v_pedido3, v_org, v_admin, 'Devolvido em dinheiro');
  if v_op->>'provedor' <> 'DINHEIRO' then raise exception 'T8: provedor: %', v_op; end if;
  v_fim := public.concluir_reembolso_pedido((v_op->>'operacao_id')::uuid, v_org, true, null, 'Devolucao em dinheiro');
  if (select status from public.pedidos where id = v_pedido3) <> 'CANCELADO' then raise exception 'T8: pedido'; end if;

  -- T9) auditoria registrada
  if (select count(*) from public.auditoria where entidade_id = v_pedido and acao like 'REEMBOLSO_%') < 3 then
    raise exception 'T9: auditoria incompleta';
  end if;
end $$;

rollback;
