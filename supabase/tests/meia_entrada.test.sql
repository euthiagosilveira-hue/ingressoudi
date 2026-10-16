-- =============================================================================
-- Ingressoudi - Testes: meia-entrada por evento
-- Arquivo: supabase/tests/meia_entrada.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if not has_function_privilege('anon', 'public.criar_reserva(uuid,text,text,text,text[],boolean[])', 'EXECUTE') then
    raise exception 'ACL: comprador anonimo precisa reservar com meia-entrada';
  end if;
  if has_function_privilege('anon', 'public.definir_meia_entrada_evento_admin(uuid,boolean)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ligar a meia-entrada';
  end if;
  if has_function_privilege('anon', 'private.anexar_meia_entrada(jsonb)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode chamar funcao interna da portaria';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.proname = 'criar_reserva' and p.pronargs = 5
  ) then
    raise exception 'ACL: assinatura antiga de criar_reserva deveria ter sido removida';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_org_slug text := 'meia-' || replace(gen_random_uuid()::text, '-', '');
  v_admin uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_ev uuid; v_ev_barato uuid; v_lote uuid; v_slug text;
  v_res jsonb; v_pag jsonb; v_chk jsonb; v_ing jsonb;
  v_token text; v_token_inteira text;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Meia A', v_org_slug, 1.00) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Meia B', 'meia-b-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_b;
  update public.organizacoes set aprovada = true where id in (v_org, v_org_b);

  insert into auth.users (id) values (v_admin), (v_admin_b);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_admin, 'Adm', 'meia_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_admin_b, 'Adm B', 'meia_b_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_admin, 'ADMINISTRADOR'), (v_org_b, v_admin_b, 'ADMINISTRADOR');

  v_slug := 'meia-ev-' || replace(gen_random_uuid()::text,'-','');
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Pagode Meia', v_slug, now() + interval '5 days', 'Casa', 'Rua', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote 1', 1, 50, 50.00, 'MANUAL', 'ATIVO') returning id into v_lote;

  -- T1) padrao: meia desligada; reserva sem meias continua igual ----------------
  if (select meia_entrada_ativa from public.eventos where id = v_ev) then
    raise exception 'T1: meia-entrada deveria comecar desligada';
  end if;
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana']);
  if (v_res->>'valor_total')::numeric <> 51 or (v_res->>'quantidade_meia')::int <> 0 then
    raise exception 'T1: reserva sem meia incorreta: %', v_res;
  end if;
  begin
    perform public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana'], array[true]);
    raise exception 'T1: deveria recusar meia com a opcao desligada';
  exception when others then
    if position('meia-entrada nao disponivel' in lower(sqlerrm)) = 0 then raise exception 'T1: erro inesperado: %', sqlerrm; end if;
  end;

  -- T2) admin de outra casa nao liga; admin da casa liga ------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);
  begin
    perform public.definir_meia_entrada_evento_admin(v_ev, true);
    raise exception 'T2: deveria falhar';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'T2: erro inesperado: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.definir_meia_entrada_evento_admin(v_ev, true);
  if (public.obter_evento_admin(v_ev)->>'meia_entrada_ativa')::boolean is not true then
    raise exception 'T2: obter_evento_admin deveria refletir a meia ligada';
  end if;
  if not exists (select 1 from public.obter_evento_publico_organizacao(v_org_slug, v_slug) where meia_entrada_ativa) then
    raise exception 'T2: pagina publica deveria saber que o evento tem meia';
  end if;

  -- T3) 1 inteira + 2 meias: 50 + 25 + 25, taxa igual por ingresso -------------
  v_res := public.criar_reserva(v_ev, 'Comprador 2', '11999990001', null, array['Bia', 'Caio', 'Duda'], array[false, true, true]);
  if (v_res->>'valor_ingressos')::numeric <> 100 or (v_res->>'valor_taxa_total')::numeric <> 3
     or (v_res->>'valor_total')::numeric <> 103 or (v_res->>'quantidade_meia')::int <> 2
     or (v_res->>'valor_unitario')::numeric <> 50 or (v_res->>'valor_unitario_meia')::numeric <> 25 then
    raise exception 'T3: composicao incorreta: %', v_res;
  end if;
  if (select count(*) from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid and meia and valor_unitario = 25) <> 2
     or (select count(*) from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid and not meia and valor_unitario = 50) <> 1 then
    raise exception 'T3: ingressos gravados com valor/meia errados';
  end if;
  if jsonb_path_query_first(v_res, '$.ingressos[*] ? (@.participante_nome == "Caio")') ->> 'meia' <> 'true' then
    raise exception 'T3: retorno deveria marcar Caio como meia: %', v_res;
  end if;

  -- T4) checkout mostra o valor real dos ingressos --------------------------------
  v_chk := public.obter_checkout_pedido((v_res->>'checkout_token')::uuid);
  if (v_chk->>'valor_ingressos')::numeric <> 100 or (v_chk->>'quantidade_meia')::int <> 2 then
    raise exception 'T4: checkout incorreto: %', v_chk;
  end if;

  -- T5) pagamento usa o total com meias e libera os ingressos com a marca ---------
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  if (v_pag->>'valor')::numeric <> 103 then
    raise exception 'T5: pagamento deveria ser de 103 (obtido %)', v_pag->>'valor';
  end if;
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-meia-1', null);
  v_ing := public.obter_ingressos_checkout((v_res->>'checkout_token')::uuid);
  if (select count(*) from jsonb_array_elements(v_ing->'ingressos') x where (x->>'meia')::boolean) <> 2 then
    raise exception 'T5: ingressos do comprador deveriam indicar 2 meias: %', v_ing;
  end if;
  if (select count(*) from jsonb_array_elements(public.obter_pedido_admin((v_res->>'pedido_id')::uuid)->'ingressos') x
       where (x->>'meia')::boolean) <> 2 then
    raise exception 'T5: painel do pedido deveria indicar 2 meias';
  end if;
  select qr_token into v_token from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid and meia order by codigo limit 1;
  select qr_token into v_token_inteira from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid and not meia limit 1;

  -- T6) listas de tamanhos diferentes sao recusadas -------------------------------
  begin
    perform public.criar_reserva(v_ev, 'Comprador 3', '11999990002', null, array['Eva', 'Fabi'], array[true]);
    raise exception 'T6: deveria recusar';
  exception when others then
    if position('participantes' in lower(sqlerrm)) = 0 then raise exception 'T6: erro inesperado: %', sqlerrm; end if;
  end;

  -- T7) ingresso nao pode virar meia sem mudar o valor ----------------------------
  begin
    update public.ingressos set meia = true where qr_token = v_token_inteira;
    raise exception 'T7: deveria recusar';
  exception when others then
    if position('valor_unitario' in lower(sqlerrm)) = 0 then raise exception 'T7: erro inesperado: %', sqlerrm; end if;
  end;

  -- T8) portaria avisa que e meia (QR e nome) --------------------------------------
  update public.eventos set status = 'EM_ANDAMENTO', inicio_em = now() - interval '1 hour' where id = v_ev;
  v_res := public.registrar_entrada_qr(v_ev, v_token);
  if v_res->>'resultado' <> 'LIBERADO' or (v_res->>'meia')::boolean is not true then
    raise exception 'T8: portaria deveria liberar avisando meia: %', v_res;
  end if;
  v_res := public.registrar_entrada_qr(v_ev, v_token);
  if v_res->>'resultado' <> 'JA_UTILIZADO' or (v_res->>'meia')::boolean is not true then
    raise exception 'T8: segunda leitura deveria manter o aviso de meia: %', v_res;
  end if;
  v_res := public.registrar_entrada_nome(v_ev, (select id from public.ingressos where qr_token = v_token_inteira));
  if v_res->>'resultado' <> 'LIBERADO' or (v_res->>'meia')::boolean is not false then
    raise exception 'T8: inteira nao deveria avisar meia: %', v_res;
  end if;
  v_res := public.registrar_entrada_qr(v_ev, 'nao-existe-' || gen_random_uuid()::text);
  if v_res->>'resultado' <> 'NAO_ENCONTRADO' or coalesce((v_res->>'meia')::boolean, false) then
    raise exception 'T8: QR inexistente: %', v_res;
  end if;
  if (select count(*) from jsonb_array_elements(public.buscar_ingressos_por_nome(v_ev, 'Duda')) x where (x->>'meia')::boolean) <> 1 then
    raise exception 'T8: busca por nome deveria indicar a meia';
  end if;

  -- T9) taxa absorvida com meia mais barata que a taxa: comissao limitada a meia ---
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada, meia_entrada_ativa)
  values (v_org, 'Barato', 'meia-bar-' || replace(gen_random_uuid()::text,'-',''), now() + interval '5 days', 'C', 'R', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS', false, true)
  returning id into v_ev_barato;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev_barato, 'Promo', 1, 50, 1.25, 'MANUAL', 'ATIVO');
  v_res := public.criar_reserva(v_ev_barato, 'Comprador 4', '11999990003', null, array['Gil', 'Hugo'], array[true, false]);
  if (v_res->>'valor_unitario_meia')::numeric <> 0.63 or (v_res->>'valor_total')::numeric <> 1.88
     or (v_res->>'taxa_servico_unitaria')::numeric <> 0.63 or (v_res->>'valor_taxa_total')::numeric <> 1.26 then
    raise exception 'T9: absorvida com meia incorreta: %', v_res;
  end if;
end $$;

select 'meia_entrada: todos os testes passaram' as resultado;

rollback;
