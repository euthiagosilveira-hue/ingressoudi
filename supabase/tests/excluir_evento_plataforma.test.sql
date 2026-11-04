-- =============================================================================
-- Ingressoudi - Testes: excluir evento (super admin)
-- Arquivo: supabase/tests/excluir_evento_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.excluir_evento_plataforma(uuid, boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resumo_exclusao_evento(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode excluir evento';
  end if;
end $$;

do $$
declare
  v_org uuid; v_org_b uuid;
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_ev uuid; v_ev_vazio uuid; v_ev_b uuid; v_lote uuid; v_ingresso uuid;
  v_res jsonb; v_pag jsonb; v_resumo jsonb; v_aud jsonb;
begin
  insert into public.organizacoes (nome, slug, lista_vip_ativa) values ('Exc A', 'exc-a-' || substr(md5(random()::text),1,10), true) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('Exc B', 'exc-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'exc_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Adm', 'exc_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_super, 'ADMINISTRADOR'), (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_super, v_admin);

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.criar_evento_admin('Demo Cliente', 'demo-cliente', null, null,
                                     now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev := (v_res->>'evento_id')::uuid;
  v_res := public.criar_lote_admin(v_ev, 'Lote', 10, 1, 'MANUAL', null);
  v_lote := (v_res->>'lote_id')::uuid;
  perform public.ativar_lote_manual(v_lote);
  v_res := public.criar_evento_admin('Demo Vazio', 'demo-vazio', null, null,
                                     now() + interval '4 days', 'Casa', 'Rua', 100, 50, 'RASCUNHO', 'ENCERRADAS');
  v_ev_vazio := (v_res->>'evento_id')::uuid;
  perform public.criar_lista_vip_admin(v_ev, 'Convidado VIP');

  -- evento de outra casa: nao pode ser afetado
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values (v_org_b, 'Evento B', 'exc-ev-' || substr(md5(random()::text),1,8), now() + interval '9 days', 'Casa B', 'Rua', 100, 80, 'AGENDADO', 'RASCUNHO', 'ENCERRADAS')
  returning id into v_ev_b;

  -- vendas: uma paga online, uma reserva com Pix pendente, uma venda na porta
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'C1', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'exc-1', null);
  v_res := public.criar_reserva(v_ev, 'C2', '11999990001', null, array['Caio']);
  perform public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.criar_venda_manual_admin(v_ev, v_lote, 'Porta', '11999990002', array['Duda']);
  select id into v_ingresso from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid limit 1;
  perform public.iniciar_evento_agora(v_ev);
  v_res := private.processar_entrada(v_ev, v_ingresso, v_super, 'QR_CODE');
  if v_res->>'resultado' <> 'LIBERADO' then
    raise exception 'setup: entrada deveria ser liberada: %', v_res;
  end if;

  -- T1) administrador comum nao exclui nem ve o resumo -------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.excluir_evento_plataforma(v_ev_vazio, true);
    raise exception 'T1: admin comum nao deveria excluir';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;
  begin
    perform public.resumo_exclusao_evento(v_ev);
    raise exception 'T1: admin comum nao deveria ver o resumo';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1b: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);

  -- T2) resumo conta tudo -------------------------------------------------------
  v_resumo := public.resumo_exclusao_evento(v_ev);
  if (v_resumo->>'pedidos')::int <> 3 or (v_resumo->>'pedidos_pagos')::int <> 2
     or (v_resumo->>'pedidos_pagos_online')::int <> 1 or (v_resumo->>'pix_pendentes')::int <> 1
     or (v_resumo->>'ingressos')::int <> 4 or (v_resumo->>'entradas')::int <> 1
     or (v_resumo->>'lista_vip')::int <> 1 or (v_resumo->>'lotes')::int <> 1 or (v_resumo->>'setores')::int <> 1 then
    raise exception 'T2: resumo: %', v_resumo;
  end if;

  -- T3) com vendas pagas, sem confirmar, nada e apagado -------------------------
  begin
    perform public.excluir_evento_plataforma(v_ev);
    raise exception 'T3: deveria exigir confirmacao das vendas pagas';
  exception when others then
    if position('EVENTO_COM_VENDAS_PAGAS' in sqlerrm) = 0 then raise exception 'T3: %', sqlerrm; end if;
  end;
  if not exists (select 1 from public.eventos where id = v_ev) then
    raise exception 'T3: evento nao deveria ter sido apagado';
  end if;

  -- T4) evento sem vendas sai direto ------------------------------------------
  perform public.excluir_evento_plataforma(v_ev_vazio);
  if exists (select 1 from public.eventos where id = v_ev_vazio)
     or exists (select 1 from public.setores where evento_id = v_ev_vazio) then
    raise exception 'T4: evento vazio deveria ter sumido';
  end if;

  -- T5) confirmando, apaga o evento e tudo que depende dele -------------------
  v_res := public.excluir_evento_plataforma(v_ev, true);
  if (v_res->>'pedidos')::int <> 3 then raise exception 'T5: retorno: %', v_res; end if;
  if exists (select 1 from public.eventos where id = v_ev)
     or exists (select 1 from public.pedidos where evento_id = v_ev)
     or exists (select 1 from public.ingressos where evento_id = v_ev)
     or exists (select 1 from public.lotes where evento_id = v_ev)
     or exists (select 1 from public.setores where evento_id = v_ev)
     or exists (select 1 from public.entradas where evento_id = v_ev)
     or exists (select 1 from public.tentativas_entrada where evento_id = v_ev)
     or exists (select 1 from public.lista_vip where evento_id = v_ev) then
    raise exception 'T5: sobrou dado do evento';
  end if;
  if exists (select 1 from public.pagamentos g where g.organizacao_id = v_org) then
    raise exception 'T5: sobrou pagamento';
  end if;

  -- T6) copia de seguranca na auditoria ---------------------------------------
  select dados_anteriores into v_aud from public.auditoria
   where acao = 'EVENTO_EXCLUIDO' and entidade_id = v_ev;
  if v_aud is null or v_aud->'evento'->>'nome' <> 'Demo Cliente'
     or jsonb_array_length(v_aud->'pedidos') <> 3 or jsonb_array_length(v_aud->'ingressos') <> 4 then
    raise exception 'T6: auditoria: %', v_aud;
  end if;

  -- T7) evento de outra casa continua la; id inexistente da erro claro -------
  if not exists (select 1 from public.eventos where id = v_ev_b) then
    raise exception 'T7: evento da casa B foi afetado';
  end if;
  begin
    perform public.excluir_evento_plataforma(v_ev);
    raise exception 'T7: deveria dizer que o evento nao existe';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'T7b: %', sqlerrm; end if;
  end;

  raise notice 'excluir_evento_plataforma: todos os testes passaram';
end $$;

rollback;
