-- =============================================================================
-- Ingressoudi - Testes: modo suporte do super admin e Painel da plataforma
-- Arquivo: supabase/tests/modo_suporte_painel_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.obter_painel_plataforma(timestamptz)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ver o painel da plataforma';
  end if;
  if has_function_privilege('anon', 'public.sair_modo_suporte()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode executar sair_modo_suporte';
  end if;
  if not has_function_privilege('authenticated', 'public.obter_painel_plataforma(timestamptz)', 'EXECUTE') then
    raise exception 'ACL: authenticated deveria executar (a regra fica na funcao)';
  end if;
end $$;

do $$
declare
  v_org_a uuid; v_org_b uuid; v_org_off uuid;
  v_super uuid := gen_random_uuid();
  v_dono_b uuid := gen_random_uuid();
  v_comum uuid := gen_random_uuid();
  v_ev uuid;
  v_res jsonb; v_pag jsonb; v_s jsonb; v_p jsonb; v_x jsonb;
begin
  insert into public.organizacoes (nome, slug) values ('Sup A', 'sup-a-' || substr(md5(random()::text),1,10)) returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Sup B', 'sup-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into public.organizacoes (nome, slug, ativo) values ('Sup Off', 'sup-o-' || substr(md5(random()::text),1,10), false) returning id into v_org_off;

  insert into auth.users (id) values (v_super), (v_dono_b), (v_comum);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'sup_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_dono_b, 'Dono B', 'sup_b_' || replace(v_dono_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_comum, 'Comum A', 'sup_c_' || replace(v_comum::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_super, 'ADMINISTRADOR'),
    (v_org_a, v_comum, 'ADMINISTRADOR'),
    (v_org_b, v_dono_b, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org_a where id in (v_super, v_comum);
  update public.usuarios set organizacao_ativa_id = v_org_b where id = v_dono_b;

  -- Evento da casa B comecando daqui a pouco, com venda online paga de valor alto
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, publicado_em)
  values (v_org_b, 'Show Suporte', 'sup-ev-' || substr(md5(random()::text),1,8), now() + interval '1 minute', 'Casa B', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', 'ABERTAS', now())
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote', 1, 50, 99999.00, 'MANUAL', 'ATIVO');

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'sup-1', null);
  -- Pix recusado na casa B (alerta)
  v_res := public.criar_reserva(v_ev, 'Outro', '11999990001', null, array['Caio']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  update public.pagamentos set status = 'REJEITADO', atualizado_em = now() where id = (v_pag->>'pagamento_id')::uuid;

  -- M1) administrador comum nao entra em casa alheia -----------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_comum::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_comum::text, true);
  begin
    perform public.definir_organizacao_ativa(v_org_b);
    raise exception 'M1: admin comum nao deveria entrar na casa B';
  exception when others then
    if position('nao encontrada' in lower(sqlerrm)) = 0 then raise exception 'M1: %', sqlerrm; end if;
  end;
  if private.em_modo_suporte() then raise exception 'M1: admin comum nunca esta em modo suporte'; end if;
  begin
    perform public.obter_painel_plataforma(null);
    raise exception 'M1: admin comum nao deveria ver o painel';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'M1 painel: %', sqlerrm; end if;
  end;

  -- M2) super admin na propria casa: nao e modo suporte ---------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_s := public.obter_sessao_operador();
  if (v_s->>'modo_suporte')::boolean or (v_s->'organizacao'->>'id')::uuid <> v_org_a then
    raise exception 'M2: sessao na casa A: %', v_s;
  end if;

  -- M3) super admin entra na casa B em modo suporte -------------------------------------
  v_s := public.definir_organizacao_ativa(v_org_b);
  if not (v_s->>'modo_suporte')::boolean or v_s->>'perfil' <> 'ADMINISTRADOR'
     or (v_s->'organizacao'->>'id')::uuid <> v_org_b or not (v_s->>'ativo')::boolean then
    raise exception 'M3: sessao em modo suporte: %', v_s;
  end if;
  if jsonb_array_length(v_s->'organizacoes') <> 1 then
    raise exception 'M3: a lista de casas do super admin nao muda: %', v_s->'organizacoes';
  end if;
  if private.organizacao_atual_id() <> v_org_b or not private.usuario_e_admin()
     or not private.evento_da_organizacao_atual(v_ev) or not private.em_modo_suporte() then
    raise exception 'M3: escopo da casa B nao foi aplicado';
  end if;
  if exists (select 1 from public.membros_organizacao where organizacao_id = v_org_b and usuario_id = v_super) then
    raise exception 'M3: super admin nao pode virar membro da equipe';
  end if;
  if not exists (select 1 from public.auditoria
                  where acao = 'MODO_SUPORTE_INICIADO' and usuario_id = v_super and organizacao_id = v_org_b) then
    raise exception 'M3: entrada em modo suporte deveria ir para a auditoria';
  end if;

  -- M4) bloqueios: Mercado Pago e usuarios ----------------------------------------------
  begin
    perform private.desconectar_mercado_pago();
    raise exception 'M4: desconectar Mercado Pago deveria falhar';
  exception when others then
    if position('modo suporte' in lower(sqlerrm)) = 0 then raise exception 'M4 mp: %', sqlerrm; end if;
  end;
  begin
    perform private.atualizar_usuario_admin(v_dono_b, 'Outro nome', 'PORTARIA', true);
    raise exception 'M4: alterar usuario deveria falhar';
  exception when others then
    if position('modo suporte' in lower(sqlerrm)) = 0 then raise exception 'M4 usuario: %', sqlerrm; end if;
  end;

  -- M5) casa inativa: nem o super admin entra --------------------------------------------
  begin
    perform public.definir_organizacao_ativa(v_org_off);
    raise exception 'M5: casa inativa deveria falhar';
  exception when others then
    if position('nao encontrada' in lower(sqlerrm)) = 0 then raise exception 'M5: %', sqlerrm; end if;
  end;

  -- M6) sair do modo suporte volta para a casa A -----------------------------------------
  v_s := public.sair_modo_suporte();
  if (v_s->>'modo_suporte')::boolean or (v_s->'organizacao'->>'id')::uuid <> v_org_a then
    raise exception 'M6: deveria voltar para a casa A: %', v_s;
  end if;

  -- P1) painel da plataforma ---------------------------------------------------------------
  v_p := public.obter_painel_plataforma(now() - interval '7 days');
  if (v_p->'metricas'->>'casas_ativas')::int < 2 or (v_p->'metricas'->>'valor')::numeric < 199998
     or (v_p->'metricas'->>'ingressos')::int < 2 or v_p->'anterior' is null then
    raise exception 'P1: metricas: %', v_p->'metricas';
  end if;
  select x into v_x from jsonb_array_elements(v_p->'eventos') x where x->>'evento_id' = v_ev::text;
  if v_x is null or (v_x->>'vendidos')::int <> 2 or v_x->>'organizacao_nome' <> 'Sup B' then
    raise exception 'P1: evento da casa B: %', v_p->'eventos';
  end if;
  select x into v_x from jsonb_array_elements(v_p->'ranking') x where x->>'organizacao_id' = v_org_b::text;
  if v_x is null or (v_x->>'valor')::numeric < 199998 then
    raise exception 'P1: ranking: %', v_p->'ranking';
  end if;
  select x into v_x from jsonb_array_elements(v_p->'alertas'->'pix_recusados_24h') x where x->>'organizacao_id' = v_org_b::text;
  if v_x is null or (v_x->>'quantidade')::int <> 1 then
    raise exception 'P1: pix recusado: %', v_p->'alertas';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_p->'alertas'->'casas_sem_mercado_pago') x
                  where x->>'organizacao_id' = v_org_b::text) then
    raise exception 'P1: casa B esta sem Mercado Pago: %', v_p->'alertas';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_p->'atividade') x
                  where x->>'tipo' = 'VENDA' and x->>'evento_id' = v_ev::text) then
    raise exception 'P1: venda deveria aparecer na atividade: %', v_p->'atividade';
  end if;
  if v_p::text ilike '%token%' or v_p::text ilike '%telefone%' then
    raise exception 'P1: o painel nao pode trazer tokens nem telefones';
  end if;

  -- P2) desde sempre: sem comparacao com periodo anterior --------------------------------
  v_p := public.obter_painel_plataforma(null);
  if v_p->'anterior' <> 'null'::jsonb then raise exception 'P2: anterior deveria ser null: %', v_p->'anterior'; end if;
end $$;

rollback;
