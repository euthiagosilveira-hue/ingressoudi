-- =============================================================================
-- Ingressoudi - Testes: eventos de todas as organizacoes (super admin)
-- Arquivo: supabase/tests/eventos_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.listar_eventos_plataforma()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode listar os eventos da plataforma';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_ev uuid; v_ev_b uuid; v_lote uuid;
  v_res jsonb; v_pag jsonb; v_lista jsonb; v_a jsonb; v_b jsonb;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Plat A', 'plat-a-' || substr(md5(random()::text),1,10), 2.00) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Plat B', 'plat-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'plat_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Adm', 'plat_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  -- o super admin NAO e membro da casa B: mesmo assim deve ver o evento dela
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_super, 'ADMINISTRADOR'), (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_super, v_admin);

  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada)
  values (v_org, 'Evento A', 'plat-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa A', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS', true)
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Primeiro lote', 1, 50, 10.00, 'MANUAL', 'ATIVO') returning id into v_lote;
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org_b, 'Evento B', 'plat-ev-' || substr(md5(random()::text),1,8), now() + interval '9 days', 'Casa B', 'Rua', 100, 80, 'AGENDADO', 'RASCUNHO', 'ENCERRADAS')
  returning id into v_ev_b;

  -- venda online paga: 2 x 10 (+2 x 2,00) ; reserva nao paga nao entra
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'C1', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'plat-1', null);
  v_res := public.criar_reserva(v_ev, 'C2', '11999990001', null, array['Caio']);

  -- T1) administrador comum nao acessa ------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.listar_eventos_plataforma();
    raise exception 'T1: admin comum nao deveria acessar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  -- T2) super admin ve os eventos das duas casas --------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_lista := public.listar_eventos_plataforma();
  select x into v_a from jsonb_array_elements(v_lista) x where x->>'evento_id' = v_ev::text;
  select x into v_b from jsonb_array_elements(v_lista) x where x->>'evento_id' = v_ev_b::text;
  if v_a is null or v_b is null then
    raise exception 'T2: eventos ausentes: A=% B=%', v_a, v_b;
  end if;
  if v_b->>'organizacao_nome' <> 'Plat B' or v_b->>'publicacao_status' <> 'RASCUNHO' then
    raise exception 'T2: casa B: %', v_b;
  end if;

  -- T3) numeros do evento A ------------------------------------------------------
  if (v_a->>'vendidos')::int <> 2 or (v_a->>'pedidos_pagos')::int <> 1
     or (v_a->>'valor_vendido')::numeric <> 24 or (v_a->>'taxa_plataforma')::numeric <> 4 then
    raise exception 'T3: numeros: %', v_a;
  end if;
  if v_a->'lote_atual'->>'nome' <> 'Primeiro lote' or (v_a->'lote_atual'->>'preco')::numeric <> 10 then
    raise exception 'T3: lote atual: %', v_a->'lote_atual';
  end if;
  if v_b->'lote_atual' <> 'null'::jsonb or (v_b->>'vendidos')::int <> 0 then
    raise exception 'T3: evento B sem lote: %', v_b;
  end if;

  -- T4) ordem: evento mais distante primeiro -------------------------------------
  if (select min(o) from jsonb_array_elements(v_lista) with ordinality t(x, o) where x->>'evento_id' = v_ev_b::text)
     > (select min(o) from jsonb_array_elements(v_lista) with ordinality t(x, o) where x->>'evento_id' = v_ev::text) then
    raise exception 'T4: ordem inesperada';
  end if;
end $$;

rollback;
