-- =============================================================================
-- Ingressoudi - Testes: modo demonstracao (iniciar evento agora / reabrir vendas)
-- Arquivo: supabase/tests/evento_demonstracao.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.iniciar_evento_agora(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.reabrir_vendas_demonstracao(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode iniciar evento';
  end if;
end $$;

do $$
declare
  v_org uuid;
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_ev uuid; v_lote uuid; v_res jsonb; v_ingresso uuid; v_inicio timestamptz;
begin
  insert into public.organizacoes (nome, slug) values ('Demo', 'demo-' || substr(md5(random()::text),1,10)) returning id into v_org;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'dm_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Adm', 'dm_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_super, 'ADMINISTRADOR'), (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_super, v_admin);

  -- evento futuro, publicado, vendas abertas, lote ativo
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.criar_evento_admin('Show Demo', 'show-demo', null, null,
                                     now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev := (v_res->>'evento_id')::uuid;
  v_res := public.criar_lote_admin(v_ev, 'Lote', 10, 1, 'MANUAL', null);
  v_lote := (v_res->>'lote_id')::uuid;
  perform public.ativar_lote_manual(v_lote);
  v_res := public.criar_venda_manual_admin(v_ev, v_lote, 'Comprador', '11999990000', array['Ana']);
  select id into v_ingresso from public.ingressos where pedido_id = (v_res->>'pedido_id')::uuid limit 1;

  if private.calcular_situacao_venda(v_ev) <> 'DISPONIVEL' then
    raise exception 'setup: venda deveria estar disponivel';
  end if;

  -- T1) antes de iniciar, a portaria recusa (evento ainda nao iniciado) --------
  v_res := private.processar_entrada(v_ev, v_ingresso, v_super, 'QR_CODE');
  if v_res->>'resultado' <> 'INVALIDO' then
    raise exception 'T1: antes de iniciar deveria recusar: %', v_res;
  end if;

  -- T2) administrador comum nao usa o modo demonstracao ------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.iniciar_evento_agora(v_ev);
    raise exception 'T2: admin comum nao deveria iniciar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T2: %', sqlerrm; end if;
  end;

  -- T3) super admin inicia: EM_ANDAMENTO, vendas online encerradas -------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.iniciar_evento_agora(v_ev);
  if (select status::text || '/' || vendas_status::text from public.eventos where id = v_ev) <> 'EM_ANDAMENTO/ENCERRADAS' then
    raise exception 'T3: status apos iniciar: %', v_res;
  end if;
  if private.calcular_situacao_venda(v_ev) <> 'EVENTO_EM_ANDAMENTO' then
    raise exception 'T3: vendas online deveriam estar fechadas';
  end if;
  if not exists (select 1 from public.auditoria where entidade_id = v_ev and acao = 'EVENTO_INICIADO_MANUAL') then
    raise exception 'T3: sem auditoria';
  end if;

  -- T4) portaria libera a entrada ---------------------------------------------
  v_res := private.processar_entrada(v_ev, v_ingresso, v_super, 'QR_CODE');
  if v_res->>'resultado' <> 'LIBERADO' then
    raise exception 'T4: entrada deveria ser liberada: %', v_res;
  end if;

  -- T5) nao inicia duas vezes ------------------------------------------------
  begin
    perform public.iniciar_evento_agora(v_ev);
    raise exception 'T5: deveria recusar evento ja iniciado';
  exception when others then
    if position('agendado' in lower(sqlerrm)) = 0 then raise exception 'T5: %', sqlerrm; end if;
  end;

  -- T6) reabrir vendas: volta para AGENDADO/ABERTAS e mantem horario futuro ----
  select inicio_em into v_inicio from public.eventos where id = v_ev;
  v_res := public.reabrir_vendas_demonstracao(v_ev);
  if (select status::text || '/' || vendas_status::text from public.eventos where id = v_ev) <> 'AGENDADO/ABERTAS' then
    raise exception 'T6: status apos reabrir: %', v_res;
  end if;
  if (select inicio_em from public.eventos where id = v_ev) <> v_inicio then
    raise exception 'T6: horario futuro nao deveria mudar';
  end if;
  if private.calcular_situacao_venda(v_ev) <> 'DISPONIVEL' then
    raise exception 'T6: venda deveria voltar a ficar disponivel';
  end if;

  -- T7) horario ja passou: reabrir adia para o futuro -------------------------
  perform public.iniciar_evento_agora(v_ev);
  update public.eventos set inicio_em = now() - interval '2 hours' where id = v_ev;
  perform public.reabrir_vendas_demonstracao(v_ev);
  if (select inicio_em from public.eventos where id = v_ev) <= now() then
    raise exception 'T7: horario deveria ir para o futuro';
  end if;
  if private.calcular_situacao_venda(v_ev) <> 'DISPONIVEL' then
    raise exception 'T7: venda deveria estar disponivel';
  end if;

  -- T8) reabrir exige EM_ANDAMENTO ------------------------------------------
  begin
    perform public.reabrir_vendas_demonstracao(v_ev);
    raise exception 'T8: deveria recusar evento agendado';
  exception when others then
    if position('em_andamento' in lower(sqlerrm)) = 0 then raise exception 'T8: %', sqlerrm; end if;
  end;
end $$;

rollback;
