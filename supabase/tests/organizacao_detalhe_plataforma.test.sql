-- =============================================================================
-- Ingressoudi - Testes: detalhe de uma casa (Plataforma, somente super admin)
-- Arquivo: supabase/tests/organizacao_detalhe_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.obter_organizacao_plataforma(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ver o detalhe das casas';
  end if;
  if not has_function_privilege('authenticated', 'public.obter_organizacao_plataforma(uuid)', 'EXECUTE') then
    raise exception 'ACL: authenticated deveria executar (a regra fica na funcao)';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_super uuid := gen_random_uuid();
  v_dono uuid := gen_random_uuid();
  v_socio uuid := gen_random_uuid();
  v_port uuid := gen_random_uuid();
  v_dono_b uuid := gen_random_uuid();
  v_ev uuid; v_ev_rasc uuid;
  v_res jsonb; v_pag jsonb; v_d jsonb; v_e jsonb;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Det A', 'det-a-' || substr(md5(random()::text),1,10), 2.00) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Det B', 'det-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;

  insert into auth.users (id) values (v_super), (v_dono), (v_socio), (v_port), (v_dono_b);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin, termos_versao, termos_aceitos_em) values
    (v_super, 'Super', 'det_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true, null, null),
    (v_dono, 'Dono A', 'det_d_' || replace(v_dono::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, '2026-10', now()),
    (v_socio, 'Socio A', 'det_so_' || replace(v_socio::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, null, null),
    (v_port, 'Porteiro A', 'det_p_' || replace(v_port::text,'-','') || '@test.local', 'PORTARIA', true, false, null, null),
    (v_dono_b, 'Dono B', 'det_b_' || replace(v_dono_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, null, null);

  -- O socio entrou antes, mas o dono e quem registrou a casa (auditoria)
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, criado_em) values
    (v_org, v_socio, 'ADMINISTRADOR', now() - interval '2 days'),
    (v_org, v_dono, 'ADMINISTRADOR', now() - interval '1 day'),
    (v_org, v_port, 'PORTARIA', now()),
    (v_org_b, v_dono_b, 'ADMINISTRADOR', now());
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, organizacao_id)
  values (v_dono, 'ORGANIZACAO_CADASTRADA', 'organizacoes', v_org, v_org);
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_dono, v_socio, v_port);
  update public.usuarios set organizacao_ativa_id = v_org_b where id = v_dono_b;

  -- Evento publicado com venda online paga (2 x 10 + taxa 2 x 2,00 repassada)
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada)
  values (v_org, 'Show A', 'det-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa A', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS', true)
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Primeiro lote', 1, 50, 10.00, 'MANUAL', 'ATIVO');
  -- Evento em rascunho, sem vendas
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Rascunho A', 'det-rs-' || substr(md5(random()::text),1,8), now() + interval '20 days', 'Casa A', 'Rua', 100, 80, 'AGENDADO', 'RASCUNHO', 'ENCERRADAS')
  returning id into v_ev_rasc;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'C1', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'det-1', null);
  -- reserva nao paga nao conta
  v_res := public.criar_reserva(v_ev, 'C2', '11999990001', null, array['Caio']);

  -- T1) administrador comum nao acessa, nem a propria casa --------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_dono::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_dono::text, true);
  begin
    perform public.obter_organizacao_plataforma(v_org);
    raise exception 'T1: admin comum nao deveria acessar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);

  -- T2) casa inexistente ----------------------------------------------------------------
  begin
    perform public.obter_organizacao_plataforma(gen_random_uuid());
    raise exception 'T2: casa inexistente deveria falhar';
  exception when others then
    if position('nao encontrada' in sqlerrm) = 0 then raise exception 'T2: %', sqlerrm; end if;
  end;

  -- T3) super admin (sem ser membro) ve a casa A, com dono e equipe ------------------
  v_d := public.obter_organizacao_plataforma(v_org);
  if v_d->'organizacao'->>'nome' <> 'Det A' then raise exception 'T3: casa: %', v_d->'organizacao'; end if;
  if v_d->'dono'->>'usuario_id' <> v_dono::text or v_d->'dono'->>'termos_versao' <> '2026-10' then
    raise exception 'T3: dono: %', v_d->'dono';
  end if;
  if jsonb_array_length(v_d->'equipe') <> 3 then raise exception 'T3: equipe: %', v_d->'equipe'; end if;
  if (v_d->'equipe'->0->>'dono')::boolean is distinct from true then
    raise exception 'T3: o dono deveria vir primeiro na equipe: %', v_d->'equipe';
  end if;
  if v_d->'organizacao'->'mercado_pago' <> 'null'::jsonb then
    raise exception 'T3: casa sem Mercado Pago: %', v_d->'organizacao';
  end if;

  -- T4) metricas ----------------------------------------------------------------------
  if (v_d->'metricas'->>'eventos_total')::int <> 2
     or (v_d->'metricas'->>'eventos_publicados')::int <> 1
     or (v_d->'metricas'->>'eventos_ativos')::int <> 1
     or (v_d->'metricas'->>'eventos_rascunho')::int <> 1
     or (v_d->'metricas'->>'ingressos_vendidos')::int <> 2
     or (v_d->'metricas'->>'pedidos_pagos')::int <> 1
     or (v_d->'metricas'->>'valor_vendido')::numeric <> 24
     or (v_d->'metricas'->>'valor_online')::numeric <> 24
     or (v_d->'metricas'->>'valor_dinheiro')::numeric <> 0
     or (v_d->'metricas'->>'taxa_plataforma')::numeric <> 4 then
    raise exception 'T4: metricas: %', v_d->'metricas';
  end if;

  -- T5) numeros por evento --------------------------------------------------------------
  select x into v_e from jsonb_array_elements(v_d->'eventos') x where x->>'evento_id' = v_ev::text;
  if v_e is null or (v_e->>'vendidos')::int <> 2 or (v_e->>'valor_vendido')::numeric <> 24 or (v_e->>'taxa_plataforma')::numeric <> 4 then
    raise exception 'T5: evento A: %', v_e;
  end if;
  select x into v_e from jsonb_array_elements(v_d->'eventos') x where x->>'evento_id' = v_ev_rasc::text;
  if v_e is null or (v_e->>'vendidos')::int <> 0 or (v_e->>'valor_vendido')::numeric <> 0 then
    raise exception 'T5: rascunho: %', v_e;
  end if;

  -- T6) isolamento: a casa B nao traz nada da casa A ----------------------------------
  v_d := public.obter_organizacao_plataforma(v_org_b);
  if v_d->'dono'->>'usuario_id' <> v_dono_b::text then raise exception 'T6: dono B: %', v_d->'dono'; end if;
  if (v_d->'metricas'->>'eventos_total')::int <> 0 or jsonb_array_length(v_d->'eventos') <> 0
     or (v_d->'metricas'->>'valor_vendido')::numeric <> 0 then
    raise exception 'T6: casa B deveria estar vazia: %', v_d;
  end if;

  -- T7) nada sensivel do Mercado Pago sai ---------------------------------------------
  if v_d::text ilike '%token%' then raise exception 'T7: o detalhe nao pode trazer tokens'; end if;
end $$;

select 'organizacao_detalhe_plataforma: todos os testes passaram' as resultado;

rollback;
