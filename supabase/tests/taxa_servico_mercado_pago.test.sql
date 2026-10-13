-- =============================================================================
-- Ingressoudi - Testes: taxa de servico e conexao Mercado Pago (Fase 2A)
-- Arquivo: supabase/tests/taxa_servico_mercado_pago.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_table_privilege('authenticated', 'public.organizacoes_mercado_pago', 'SELECT')
     or has_table_privilege('anon', 'public.organizacoes_mercado_pago', 'SELECT') then
    raise exception 'ACL: tokens do Mercado Pago nao podem ser lidos diretamente';
  end if;
  if has_function_privilege('anon', 'public.obter_status_mercado_pago()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode ver status do Mercado Pago';
  end if;
  if not has_function_privilege('anon', 'public.obter_taxa_evento_publico(text)', 'EXECUTE') then
    raise exception 'ACL: pagina publica precisa ler a taxa';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_admin uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_super uuid := gen_random_uuid();
  v_ev uuid; v_ev_barato uuid; v_lote uuid; v_slug text;
  v_res jsonb; v_pag jsonb;
begin
  insert into public.organizacoes (nome, slug, taxa_servico) values ('Taxa A', 'tx-a-' || replace(gen_random_uuid()::text,'-',''), 1.50) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Taxa B', 'tx-b-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_b;

  if (select taxa_servico from public.organizacoes where id = v_org_b) <> 1.00 then
    raise exception 'T0: taxa padrao deveria ser R$ 1,00';
  end if;

  insert into auth.users (id) values (v_admin), (v_admin_b), (v_super);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_admin, 'Adm', 'tx_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_admin_b, 'Adm B', 'tx_b_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_super, 'Super', 'tx_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_admin, 'ADMINISTRADOR'), (v_org_b, v_admin_b, 'ADMINISTRADOR'), (v_org, v_super, 'ADMINISTRADOR');

  v_slug := 'tx-ev-' || replace(gen_random_uuid()::text,'-','');
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org, 'Pagode Taxa', v_slug, now() + interval '5 days', 'Casa', 'Rua', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Lote 1', 1, 50, 25.00, 'MANUAL', 'ATIVO') returning id into v_lote;

  -- T1) taxa repassada (padrao): comprador paga ingresso + taxa -----------------
  v_res := public.criar_reserva(v_ev, 'Comprador', '11999990000', null, array['Ana', 'Bia']);
  if (v_res->>'valor_ingressos')::numeric <> 50 or (v_res->>'valor_taxa_total')::numeric <> 3
     or (v_res->>'valor_total')::numeric <> 53 or (v_res->>'taxa_repassada')::boolean is not true then
    raise exception 'T1: composicao incorreta: %', v_res;
  end if;
  if (select valor_taxa_total from public.pedidos where id = (v_res->>'pedido_id')::uuid) <> 3 then
    raise exception 'T1: taxa nao gravada no pedido';
  end if;

  -- pagamento usa o valor cobrado e confirma normalmente
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  if (v_pag->>'valor')::numeric <> 53 then
    raise exception 'T1: pagamento deveria ser de 53 (obtido %)', v_pag->>'valor';
  end if;
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'tx-1', null);

  v_res := public.obter_checkout_pagamento_backend((v_res->>'checkout_token')::uuid);
  if (v_res->>'valor_taxa_total')::numeric <> 3 or (v_res->>'organizacao_id')::uuid <> v_org then
    raise exception 'T1: backend deveria receber comissao e organizacao: %', v_res;
  end if;

  -- T2) admin define taxa absorvida: comprador paga so o ingresso --------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.definir_taxa_evento_admin(v_ev, false);
  if (public.obter_evento_admin(v_ev)->>'taxa_repassada')::boolean is not false then
    raise exception 'T2: obter_evento_admin deveria refletir taxa absorvida';
  end if;

  v_res := public.criar_reserva(v_ev, 'Comprador 2', '11999990001', null, array['Caio', 'Duda']);
  if (v_res->>'valor_total')::numeric <> 50 or (v_res->>'valor_taxa_total')::numeric <> 3 then
    raise exception 'T2: absorvida deveria cobrar 50 com comissao 3: %', v_res;
  end if;

  if (public.obter_taxa_evento_publico(v_slug)->>'taxa_servico')::numeric <> 0 then
    raise exception 'T2: pagina publica nao deveria mostrar taxa quando absorvida';
  end if;

  -- T3) absorvida com ingresso mais barato que a taxa: comissao limitada ao preco --
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status, taxa_repassada)
  values (v_org, 'Barato', 'tx-bar-' || replace(gen_random_uuid()::text,'-',''), now() + interval '5 days', 'C', 'R', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS', false)
  returning id into v_ev_barato;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev_barato, 'Promo', 1, 50, 1.00, 'MANUAL', 'ATIVO');
  v_res := public.criar_reserva(v_ev_barato, 'Comprador 3', '11999990002', null, array['Eva']);
  if (v_res->>'valor_total')::numeric <> 1 or (v_res->>'valor_taxa_total')::numeric <> 1 then
    raise exception 'T3: comissao nao pode passar do preco: %', v_res;
  end if;

  -- T4) admin de outra organizacao nao altera a taxa do evento -----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);
  begin
    perform public.definir_taxa_evento_admin(v_ev, true);
    raise exception 'T4: deveria falhar';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'T4: erro inesperado: %', sqlerrm; end if;
  end;

  -- T5) somente super admin define a taxa da organizacao ------------------------
  begin
    perform public.definir_taxa_organizacao(v_org_b, 0.50);
    raise exception 'T5: admin comum nao pode definir taxa';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'T5: erro inesperado: %', sqlerrm; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  perform public.definir_taxa_organizacao(v_org_b, 0.75);
  if (select taxa_servico from public.organizacoes where id = v_org_b) <> 0.75 then
    raise exception 'T5: taxa da organizacao B deveria ser 0,75';
  end if;

  -- T6) status da conexao Mercado Pago (sem expor tokens) ----------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.obter_status_mercado_pago();
  if (v_res->>'conectado')::boolean is not false or (v_res->>'taxa_servico')::numeric <> 1.50 then
    raise exception 'T6: status inicial incorreto: %', v_res;
  end if;

  insert into public.organizacoes_mercado_pago (organizacao_id, mp_user_id, access_token_cifrado, refresh_token_cifrado)
  values (v_org, '123456', 'cifrado-access', 'cifrado-refresh');
  v_res := public.obter_status_mercado_pago();
  if (v_res->>'conectado')::boolean is not true or v_res->>'mp_user_id' <> '123456' then
    raise exception 'T6: deveria estar conectado: %', v_res;
  end if;
  if v_res::text like '%cifrado%' then
    raise exception 'T6: status nao pode expor tokens';
  end if;

  -- admin B nao enxerga a conexao de A
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);
  if (public.obter_status_mercado_pago()->>'conectado')::boolean is not false then
    raise exception 'T6: organizacao B nao pode ver a conexao de A';
  end if;
  perform public.desconectar_mercado_pago();
  if not exists (select 1 from public.organizacoes_mercado_pago where organizacao_id = v_org) then
    raise exception 'T6: admin B nao pode desconectar a conta de A';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.desconectar_mercado_pago();
  if exists (select 1 from public.organizacoes_mercado_pago where organizacao_id = v_org) then
    raise exception 'T6: desconectar deveria remover a conexao';
  end if;

  -- T7) venda manual (dinheiro) nao cobra taxa ---------------------------------
  update public.eventos set taxa_repassada = true where id = v_ev;
  v_res := public.criar_venda_manual_admin(v_ev, v_lote, 'Balcao', '11999990003', array['Fabi']);
  if (select valor_taxa_total from public.pedidos where id = (v_res->>'pedido_id')::uuid) <> 0 then
    raise exception 'T7: venda manual nao deveria ter taxa';
  end if;
end $$;

select 'taxa_servico_mercado_pago: todos os testes passaram' as resultado;

rollback;
