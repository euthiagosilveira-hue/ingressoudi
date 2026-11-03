-- =============================================================================
-- Ingressoudi - Testes: setores do evento (Pista e Camarote)
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

-- ACL e assinaturas ----------------------------------------------------------------
do $$
begin
  if not has_function_privilege('anon', 'public.criar_reserva(uuid,text,text,text,text[],boolean[],uuid)', 'EXECUTE') then
    raise exception 'ACL: comprador anonimo precisa reservar escolhendo o setor';
  end if;
  if not has_function_privilege('anon', 'public.listar_setores_evento_publico(text,text)', 'EXECUTE') then
    raise exception 'ACL: pagina publica precisa listar os setores';
  end if;
  if has_function_privilege('anon', 'public.criar_setor_admin(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.renomear_setor_admin(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.excluir_setor_admin(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode mexer em setores';
  end if;
  if has_function_privilege('anon', 'private.setor_nome_ingresso(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.resumo_setores_evento(uuid)', 'EXECUTE') then
    raise exception 'ACL: ajudantes internos nao podem ficar expostos';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.proname in ('criar_reserva', 'criar_lote_admin')
       and not (p.proargnames @> array['p_setor_id'])
  ) then
    raise exception 'ACL: assinaturas antigas sem p_setor_id deveriam ter sido removidas';
  end if;
  if to_regclass('public.uq_lotes_evento_ativo') is not null then
    raise exception 'Indice de um lote ativo por evento deveria ter saido';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_org_slug text := 'set-' || replace(gen_random_uuid()::text, '-', '');
  v_admin uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_ev uuid; v_ev_unico uuid; v_slug text;
  v_pista uuid; v_camarote uuid; v_vazio uuid;
  v_lote_p1 uuid; v_lote_p2 uuid; v_lote_c1 uuid; v_lote_c2 uuid; v_lote_u uuid;
  v_res jsonb; v_pag jsonb; v_lista jsonb; v_item jsonb;
  v_token text; v_token_unico text;
  v_n integer;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Setores A', v_org_slug, 0) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Setores B', 'set-b-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_b;
  update public.organizacoes set aprovada = true where id in (v_org, v_org_b);

  insert into auth.users (id) values (v_admin), (v_admin_b);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_admin, 'Adm', 'set_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_admin_b, 'Adm B', 'set_b_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_admin, 'ADMINISTRADOR'), (v_org_b, v_admin_b, 'ADMINISTRADOR');

  v_slug := 'set-ev-' || replace(gen_random_uuid()::text,'-','');
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Pagode Setores', v_slug, now() + interval '5 days', 'Casa', 'Rua', 200, 100, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev;

  -- T1) evento novo nasce com o setor padrao -----------------------------------------
  select s.id into v_pista from public.setores s where s.evento_id = v_ev;
  if v_pista is null or (select nome from public.setores where id = v_pista) <> 'Ingresso'
     or (select organizacao_id from public.setores where id = v_pista) <> v_org then
    raise exception 'T1: evento deveria nascer com o setor Ingresso da organizacao';
  end if;

  -- T2) admin de outra casa nao mexe; admin da casa cria e renomeia ---------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);
  begin
    perform public.criar_setor_admin(v_ev, 'Camarote');
    raise exception 'T2: deveria falhar';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'T2: erro inesperado: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.renomear_setor_admin(v_pista, '  Pista ');
  if (select nome from public.setores where id = v_pista) <> 'Pista' then
    raise exception 'T2: renomear deveria limpar espacos';
  end if;
  v_res := public.criar_setor_admin(v_ev, 'Camarote');
  v_camarote := (v_res->>'setor_id')::uuid;
  if (v_res->>'ordem')::int <> 2 then raise exception 'T2: Camarote deveria ser o segundo setor: %', v_res; end if;
  begin
    perform public.criar_setor_admin(v_ev, 'camarote');
    raise exception 'T2: nome repetido deveria falhar';
  exception when others then
    if position('ja existe' in lower(sqlerrm)) = 0 then raise exception 'T2: erro inesperado: %', sqlerrm; end if;
  end;

  -- T3) lotes por setor; sem setor cai no primeiro -------------------------------------
  v_res := public.criar_lote_admin(v_ev, 'Pista 1', 3, 30, 'MANUAL', null, null);
  v_lote_p1 := (v_res->>'lote_id')::uuid;
  if (select setor_id from public.lotes where id = v_lote_p1) <> v_pista then
    raise exception 'T3: lote sem setor deveria ir para a Pista';
  end if;
  v_lote_p2 := (public.criar_lote_admin(v_ev, 'Pista 2', 10, 40, 'ESGOTAMENTO', null, v_pista)->>'lote_id')::uuid;
  v_lote_c1 := (public.criar_lote_admin(v_ev, 'Camarote 1', 2, 80, 'MANUAL', null, v_camarote)->>'lote_id')::uuid;
  v_lote_c2 := (public.criar_lote_admin(v_ev, 'Camarote 2', 5, 100, 'ESGOTAMENTO', null, v_camarote)->>'lote_id')::uuid;

  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Evento Unico', 'set-unico-' || replace(gen_random_uuid()::text,'-',''), now() + interval '5 days', 'Casa', 'Rua', 50, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev_unico;
  begin
    perform public.criar_lote_admin(v_ev_unico, 'Errado', 5, 10, 'MANUAL', null, v_camarote);
    raise exception 'T3: setor de outro evento deveria falhar';
  exception when others then
    if position('nao pertence' in lower(sqlerrm)) = 0 then raise exception 'T3: erro inesperado: %', sqlerrm; end if;
  end;

  -- T4) um lote ATIVO por setor ----------------------------------------------------------
  perform public.ativar_lote_manual(v_lote_p1);
  perform public.ativar_lote_manual(v_lote_c1);
  if (select count(*) from public.lotes where evento_id = v_ev and status = 'ATIVO') <> 2 then
    raise exception 'T4: Pista e Camarote deveriam ter um lote ativo cada';
  end if;
  begin
    update public.lotes set status = 'ATIVO' where id = v_lote_c2;
    raise exception 'T4: dois lotes ativos no mesmo setor deveriam falhar';
  exception when unique_violation then
    null;
  end;

  -- T5) pagina publica lista os dois setores ------------------------------------------
  v_lista := public.listar_setores_evento_publico(v_org_slug, (select slug from public.eventos where id = v_ev));
  if jsonb_array_length(v_lista) <> 2
     or v_lista->0->>'nome' <> 'Pista' or (v_lista->0->>'preco')::numeric <> 30
     or v_lista->1->>'nome' <> 'Camarote' or (v_lista->1->>'preco')::numeric <> 80
     or v_lista->0->>'situacao_venda' <> 'DISPONIVEL' or v_lista->1->>'situacao_venda' <> 'DISPONIVEL' then
    raise exception 'T5: setores publicos incorretos: %', v_lista;
  end if;
  if (select preco from public.obter_evento_publico_organizacao(v_org_slug, (select slug from public.eventos where id = v_ev))) <> 30 then
    raise exception 'T5: pagina do evento deveria mostrar o menor preco';
  end if;

  -- T6) reserva escolhe o setor ------------------------------------------------------
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana', 'Bia'], null, v_camarote);
  if (v_res->>'lote_id')::uuid <> v_lote_c1 or (v_res->>'setor_id')::uuid <> v_camarote
     or (v_res->>'valor_total')::numeric <> 160 then
    raise exception 'T6: reserva do camarote incorreta: %', v_res;
  end if;
  -- camarote esgotou o 1o lote: vira para o 2o so no camarote
  if (select status from public.lotes where id = v_lote_c1) <> 'ENCERRADO'
     or (select status from public.lotes where id = v_lote_c2) <> 'ATIVO'
     or (select status from public.lotes where id = v_lote_p1) <> 'ATIVO' then
    raise exception 'T6: virada deveria acontecer so no Camarote';
  end if;
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-setor-1', null);
  select i.qr_token into v_token from public.ingressos i where i.pedido_id = (v_res->>'pedido_id')::uuid order by i.codigo limit 1;

  -- sem setor: primeiro setor com lote ativo (Pista)
  v_res := public.criar_reserva(v_ev, 'Comprador 2', '11999990001', null, array['Caio']);
  if (v_res->>'lote_id')::uuid <> v_lote_p1 or (v_res->>'valor_total')::numeric <> 30 then
    raise exception 'T6: reserva sem setor deveria ir para a Pista: %', v_res;
  end if;
  begin
    perform public.criar_reserva(v_ev, 'Comprador 3', '11999990002', null, array['Duda'], null, gen_random_uuid());
    raise exception 'T6: setor inexistente deveria falhar';
  exception when others then
    if position('setor' in lower(sqlerrm)) = 0 then raise exception 'T6: erro inesperado: %', sqlerrm; end if;
  end;

  -- T7) nome "Setor · Lote" no pedido; setor na portaria e nos ingressos ---------------
  if public.obter_pedido_admin((v_res->>'pedido_id')::uuid)->>'lote_nome' <> 'Pista · Pista 1' then
    raise exception 'T7: pedido deveria mostrar setor e lote: %', public.obter_pedido_admin((v_res->>'pedido_id')::uuid)->>'lote_nome';
  end if;
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour' where id = v_ev;
  v_res := public.registrar_entrada_qr(v_ev, v_token);
  if v_res->>'resultado' <> 'LIBERADO' or v_res->>'setor_nome' <> 'Camarote' then
    raise exception 'T7: portaria deveria mostrar o setor: %', v_res;
  end if;
  v_lista := public.buscar_ingressos_por_nome(v_ev, 'Bia');
  if v_lista->0->>'setor_nome' <> 'Camarote' then
    raise exception 'T7: busca por nome deveria mostrar o setor: %', v_lista;
  end if;

  -- evento com um setor so: nada muda (sem setor_nome, nome do lote puro)
  v_lote_u := (public.criar_lote_admin(v_ev_unico, 'Lote 1', 10, 20, 'MANUAL', null, null)->>'lote_id')::uuid;
  perform public.ativar_lote_manual(v_lote_u);
  v_res := public.criar_reserva(v_ev_unico, 'Comprador U', '11999990003', null, array['Eva']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-setor-2', null);
  if public.obter_pedido_admin((v_res->>'pedido_id')::uuid)->>'lote_nome' <> 'Lote 1' then
    raise exception 'T7: evento de um setor deveria manter o nome do lote';
  end if;
  select i.qr_token into v_token_unico from public.ingressos i where i.pedido_id = (v_res->>'pedido_id')::uuid;
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour' where id = v_ev_unico;
  v_res := public.registrar_entrada_qr(v_ev_unico, v_token_unico);
  if v_res->>'resultado' <> 'LIBERADO' or v_res->>'setor_nome' is not null then
    raise exception 'T7: evento de um setor nao deveria mostrar setor: %', v_res;
  end if;

  -- T8) painel do evento: vendas por setor -------------------------------------------
  v_lista := public.obter_painel_evento_admin(v_ev)->'setores';
  select x into v_item from jsonb_array_elements(v_lista) x where x->>'nome' = 'Camarote';
  if jsonb_array_length(v_lista) <> 2 or (v_item->>'vendidos')::int <> 2 or (v_item->>'utilizados')::int <> 1
     or (v_item->>'receita')::numeric <> 160 or (v_item->>'capacidade')::int <> 7 then
    raise exception 'T8: resumo por setor incorreto: %', v_lista;
  end if;
  if jsonb_array_length(public.listar_lotes_admin(v_ev)->'setores') <> 2
     or (public.listar_lotes_admin(v_ev)->'lotes'->0->>'setor_id') is null then
    raise exception 'T8: lista de lotes deveria trazer os setores';
  end if;

  -- T9) excluir setor: so vazio e nunca o ultimo --------------------------------------
  begin
    perform public.excluir_setor_admin(v_camarote);
    raise exception 'T9: setor com lotes nao deveria ser excluido';
  exception when others then
    if position('com lotes' in lower(sqlerrm)) = 0 then raise exception 'T9: erro inesperado: %', sqlerrm; end if;
  end;
  update public.eventos set status = 'AGENDADO', inicio_em = now() + interval '5 days' where id = v_ev;
  v_vazio := (public.criar_setor_admin(v_ev, 'Area VIP')->>'setor_id')::uuid;
  if jsonb_array_length(public.listar_setores_evento_publico(v_org_slug, (select slug from public.eventos where id = v_ev))) <> 2 then
    raise exception 'T9: setor sem lote nao aparece na pagina publica';
  end if;
  perform public.excluir_setor_admin(v_vazio);
  if exists (select 1 from public.setores where id = v_vazio) then raise exception 'T9: setor vazio deveria sair'; end if;
  begin
    insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
    values (v_org, 'Evento Vazio', 'set-vazio-' || replace(gen_random_uuid()::text,'-',''), now() + interval '5 days', 'Casa', 'Rua', 50, 50, 'AGENDADO', 'RASCUNHO', 'ENCERRADAS')
    returning id into v_vazio;
    perform public.excluir_setor_admin((select id from public.setores where evento_id = v_vazio));
    raise exception 'T9: ultimo setor nao deveria sair';
  exception when others then
    if position('pelo menos um setor' in lower(sqlerrm)) = 0 then raise exception 'T9: erro inesperado: %', sqlerrm; end if;
  end;

  -- T10) encerrar o evento encerra os lotes ativos de todos os setores ------------------
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour' where id = v_ev;
  perform public.encerrar_evento(v_ev);
  select count(*) into v_n from public.lotes where evento_id = v_ev and status = 'ATIVO';
  if v_n <> 0 then raise exception 'T10: nenhum lote deveria continuar ativo (%)', v_n; end if;
end $$;

rollback;
