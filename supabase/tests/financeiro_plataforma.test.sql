-- =============================================================================
-- Ingressoudi - Testes: financeiro da plataforma (super admin)
-- Arquivo: supabase/tests/financeiro_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.financeiro_plataforma(date,date)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ver o financeiro da plataforma';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_ev uuid; v_ev_abs uuid; v_ev_b uuid; v_lote uuid; v_lote_abs uuid; v_lote_b uuid;
  v_res jsonb; v_pag jsonb; v_fin jsonb; v_a jsonb; v_b jsonb; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_base jsonb;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Fin A', 'fin-a-' || substr(md5(random()::text),1,10), 1.50) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Fin B', 'fin-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'fin_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Adm', 'fin_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_super, 'ADMINISTRADOR'), (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_super, v_admin);

  -- linha de base (outras vendas que existam no banco no periodo)
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_base := public.financeiro_plataforma(v_hoje, v_hoje)->'totais';

  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada)
  values (v_org, 'Repassada', 'fin-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS', true)
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote', 1, 50, 10.00, 'MANUAL', 'ATIVO') returning id into v_lote;
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada)
  values (v_org, 'Absorvida', 'fin-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS', false)
  returning id into v_ev_abs;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev_abs, 'Lote', 1, 50, 20.00, 'MANUAL', 'ATIVO') returning id into v_lote_abs;
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org_b, 'Casa B', 'fin-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev_b;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev_b, 'Lote', 1, 50, 30.00, 'MANUAL', 'ATIVO') returning id into v_lote_b;

  -- vendas online (anonimo): A repassada 2x10 (+2x1,50) ; A absorvida 1x20 ; B 1x30 (+1,00)
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'C1', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'fin-1', null);
  v_res := public.criar_reserva(v_ev_abs, 'C2', '11999990001', null, array['Caio']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'fin-2', null);
  v_res := public.criar_reserva(v_ev_b, 'C3', '11999990002', null, array['Duda']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'fin-3', null);
  -- reserva nao paga nao entra
  v_res := public.criar_reserva(v_ev, 'C4', '11999990003', null, array['Eva']);
  -- venda paga antiga (fora do periodo) nao entra
  v_res := public.criar_reserva(v_ev, 'C5', '11999990004', null, array['Fabi']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'fin-5', null);
  update public.pedidos set pago_em = now() - interval '40 days' where id = (v_res->>'pedido_id')::uuid;

  -- venda em dinheiro (admin A): 3 x 10, sem taxa
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.criar_venda_manual_admin(v_ev, v_lote, 'Porta', '11999990005', array['G1','G2','G3']);

  -- T1) administrador comum nao acessa -------------------------------------------
  begin
    perform public.financeiro_plataforma(v_hoje, v_hoje);
    raise exception 'T1: admin comum nao deveria acessar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  -- T2) super admin: totais do periodo (descontada a linha de base) ---------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_fin := public.financeiro_plataforma(v_hoje, v_hoje);
  -- online: 23 (20+3) + 20 + 31 = 74 ; taxa: 3 + 1,50 (absorvida, limitada ao preco) + 1 = 5,50
  if (v_fin->'totais'->>'bruto_online')::numeric - (v_base->>'bruto_online')::numeric <> 74 then
    raise exception 'T2: bruto online: %', v_fin->'totais';
  end if;
  if (v_fin->'totais'->>'taxa_plataforma')::numeric - (v_base->>'taxa_plataforma')::numeric <> 5.50 then
    raise exception 'T2: taxa plataforma: %', v_fin->'totais';
  end if;
  if (v_fin->'totais'->>'repasse_produtores')::numeric - (v_base->>'repasse_produtores')::numeric <> 68.50 then
    raise exception 'T2: repasse: %', v_fin->'totais';
  end if;
  if (v_fin->'totais'->>'ingressos_online')::int - (v_base->>'ingressos_online')::int <> 4 then
    raise exception 'T2: ingressos online: %', v_fin->'totais';
  end if;
  if (v_fin->'totais'->>'bruto_dinheiro')::numeric - (v_base->>'bruto_dinheiro')::numeric <> 30
     or (v_fin->'totais'->>'ingressos_dinheiro')::int - (v_base->>'ingressos_dinheiro')::int <> 3 then
    raise exception 'T2: dinheiro: %', v_fin->'totais';
  end if;

  -- T3) quebra por casa ----------------------------------------------------------
  select x into v_a from jsonb_array_elements(v_fin->'organizacoes') x where x->>'organizacao_id' = v_org::text;
  select x into v_b from jsonb_array_elements(v_fin->'organizacoes') x where x->>'organizacao_id' = v_org_b::text;
  if (v_a->>'taxa_plataforma')::numeric <> 4.50 or (v_a->>'bruto_online')::numeric <> 43
     or (v_a->>'pedidos_online')::int <> 2 or (v_a->>'bruto_dinheiro')::numeric <> 30 then
    raise exception 'T3: casa A: %', v_a;
  end if;
  if (v_b->>'taxa_plataforma')::numeric <> 1 or (v_b->>'repasse_produtor')::numeric <> 30 then
    raise exception 'T3: casa B: %', v_b;
  end if;

  -- T4) periodo antigo pega a venda de 40 dias atras ---------------------------
  v_fin := public.financeiro_plataforma(v_hoje - 41, v_hoje - 39);
  select x into v_a from jsonb_array_elements(v_fin->'organizacoes') x where x->>'organizacao_id' = v_org::text;
  if v_a is null or (v_a->>'bruto_online')::numeric <> 11.50 then
    raise exception 'T4: venda antiga: %', v_a;
  end if;

  -- T5) periodo invalido -------------------------------------------------------
  begin
    perform public.financeiro_plataforma(v_hoje, v_hoje - 1);
    raise exception 'T5: deveria recusar periodo invertido';
  exception when others then
    if position('periodo invalido' in lower(sqlerrm)) = 0 then raise exception 'T5: %', sqlerrm; end if;
  end;
  begin
    perform public.financeiro_plataforma(v_hoje - 400, v_hoje);
    raise exception 'T5: deveria recusar mais de 1 ano';
  exception when others then
    if position('periodo invalido' in lower(sqlerrm)) = 0 then raise exception 'T5b: %', sqlerrm; end if;
  end;
end $$;

rollback;
