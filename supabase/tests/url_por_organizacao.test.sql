-- =============================================================================
-- Ingressoudi - Testes: URL e catalogo por organizacao (Fase 3A)
-- Arquivo: supabase/tests/url_por_organizacao.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if not has_function_privilege('anon', 'public.obter_organizacao_publica(text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.listar_eventos_publicos_organizacao(text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.obter_evento_publico_organizacao(text,text)', 'EXECUTE')
     or not has_function_privilege('anon', 'public.resolver_evento_publico(text)', 'EXECUTE') then
    raise exception 'ACL: paginas publicas precisam das RPCs por organizacao';
  end if;
end $$;

do $$
declare
  v_sa text := 'url-a-' || substr(replace(gen_random_uuid()::text,'-',''), 1, 10);
  v_sb text := 'url-b-' || substr(replace(gen_random_uuid()::text,'-',''), 1, 10);
  v_org_a uuid; v_org_b uuid;
  v_admin_a uuid := gen_random_uuid();
  v_admin_b uuid := gen_random_uuid();
  v_ev_a uuid; v_ev_b uuid; v_ev_rasc uuid; v_ev_a2 uuid; v_lote uuid;
  v_res jsonb; v_n int; v_txt text;
begin
  -- T1) slug reservado e bloqueado --------------------------------------------
  begin
    insert into public.organizacoes (nome, slug) values ('Hack', 'painel');
    raise exception 'T1: slug reservado deveria ser rejeitado';
  exception when check_violation then null;
  end;
  begin
    insert into public.organizacoes (nome, slug) values ('Hack', 'eventos');
    raise exception 'T1: slug reservado (eventos) deveria ser rejeitado';
  exception when check_violation then null;
  end;

  -- logo: so https ou caminho relativo
  begin
    insert into public.organizacoes (nome, slug, logo_url) values ('Logo', 'logo-' || substr(md5(random()::text),1,8), 'data:image/png;base64,xx');
    raise exception 'T1: logo data: deveria ser rejeitado';
  exception when check_violation then null;
  end;

  insert into public.organizacoes (nome, slug, logo_url) values ('Casa A', v_sa, 'https://exemplo.com/logo.png') returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Casa B', v_sb) returning id into v_org_b;

  insert into auth.users (id) values (v_admin_a), (v_admin_b);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin_a, 'Adm A', 'url_a_' || replace(v_admin_a::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_admin_b, 'Adm B', 'url_b_' || replace(v_admin_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_admin_a, 'ADMINISTRADOR'), (v_org_b, v_admin_b, 'ADMINISTRADOR');

  -- T2) mesmo slug de evento em casas diferentes e permitido -------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_a::text, true);
  v_res := public.criar_evento_admin('Pagode A', 'pagode-sexta', null, null,
                                     now() + interval '3 days', 'Casa A', 'Rua A', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev_a := (v_res->>'evento_id')::uuid;
  v_res := public.criar_lote_admin(v_ev_a, 'Lote A', 10, 25, 'MANUAL', null);
  perform public.ativar_lote_manual((v_res->>'lote_id')::uuid);

  v_res := public.criar_evento_admin('Rascunho A', 'rascunho-a', null, null,
                                     now() + interval '3 days', 'Casa A', 'Rua A', 100, 50, 'RASCUNHO', 'ENCERRADAS');
  v_ev_rasc := (v_res->>'evento_id')::uuid;

  -- T3) mesmo slug na MESMA casa e bloqueado (criar e atualizar) -----------------
  begin
    perform public.criar_evento_admin('Dup', 'pagode-sexta', null, null,
                                      now() + interval '4 days', 'Casa A', 'Rua A', 100, 50, 'RASCUNHO', 'ENCERRADAS');
    raise exception 'T3: slug duplicado na mesma casa deveria falhar';
  exception when others then
    if position('ja existe' in lower(sqlerrm)) = 0 then raise exception 'T3 criar: %', sqlerrm; end if;
  end;
  begin
    perform public.atualizar_evento_admin(v_ev_rasc, 'Rascunho A', 'pagode-sexta', null, null,
                                          now() + interval '3 days', 'Casa A', 'Rua A', 100, 50, 'RASCUNHO', null);
    raise exception 'T3: atualizar para slug duplicado deveria falhar';
  exception when others then
    if position('ja existe' in lower(sqlerrm)) = 0 then raise exception 'T3 atualizar: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_b::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin_b::text, true);
  v_res := public.criar_evento_admin('Pagode B', 'pagode-sexta', null, null,
                                     now() + interval '5 days', 'Casa B', 'Rua B', 100, 50, 'PUBLICADO', 'ABERTAS');
  v_ev_b := (v_res->>'evento_id')::uuid;
  if v_ev_b is null then raise exception 'T2: casa B deveria poder usar o mesmo slug'; end if;

  -- casa B pode atualizar o proprio evento mantendo o slug (que existe na casa A)
  perform public.atualizar_evento_admin(v_ev_b, 'Pagode B', 'pagode-sexta', null, null,
                                        now() + interval '5 days', 'Casa B', 'Rua B', 100, 50, 'PUBLICADO', null);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- T4) catalogo por casa nao mistura casas nem mostra rascunho -------------------
  select count(*) into v_n from public.listar_eventos_publicos_organizacao(v_sa);
  if v_n <> 1 then raise exception 'T4: casa A deveria listar 1 evento (obtido %)', v_n; end if;
  if exists (select 1 from public.listar_eventos_publicos_organizacao(v_sa) where evento_id in (v_ev_b, v_ev_rasc)) then
    raise exception 'T4: catalogo da casa A vazou evento de outra casa ou rascunho';
  end if;
  select count(*) into v_n from public.listar_eventos_publicos_organizacao('nao-existe-xyz');
  if v_n <> 0 then raise exception 'T4: casa inexistente nao deveria listar nada'; end if;

  -- T5) evento por casa + slug ----------------------------------------------
  select evento_id into v_ev_a2 from public.obter_evento_publico_organizacao(v_sa, 'pagode-sexta');
  if v_ev_a2 is distinct from v_ev_a then raise exception 'T5: deveria achar o evento da casa A'; end if;
  select evento_id into v_ev_a2 from public.obter_evento_publico_organizacao(v_sb, 'pagode-sexta');
  if v_ev_a2 is distinct from v_ev_b then raise exception 'T5: deveria achar o evento da casa B'; end if;
  select count(*) into v_n from public.obter_evento_publico_organizacao(v_sa, 'rascunho-a');
  if v_n <> 0 then raise exception 'T5: rascunho nao pode ser publico'; end if;
  select count(*) into v_n from public.obter_evento_publico_organizacao(upper(v_sa), 'PAGODE-SEXTA');
  if v_n <> 1 then raise exception 'T5: busca deveria ignorar maiusculas'; end if;

  select organizacao_nome, organizacao_logo_url, taxa_servico into v_txt, v_res, v_n
    from (select organizacao_nome, to_jsonb(organizacao_logo_url) as organizacao_logo_url, taxa_servico::int
            from public.obter_evento_publico_organizacao(v_sa, 'pagode-sexta')) x;
  if v_txt <> 'Casa A' or v_res #>> '{}' <> 'https://exemplo.com/logo.png' or v_n <> 1 then
    raise exception 'T5: dados da casa/taxa incorretos (% / % / %)', v_txt, v_res, v_n;
  end if;

  -- T6) organizacao publica ---------------------------------------------------
  v_res := public.obter_organizacao_publica(v_sa);
  if v_res->>'nome' <> 'Casa A' or (v_res->>'organizacao_id')::uuid <> v_org_a then
    raise exception 'T6: organizacao publica incorreta: %', v_res;
  end if;
  update public.organizacoes set ativo = false where id = v_org_b;
  if public.obter_organizacao_publica(v_sb) is not null then
    raise exception 'T6: organizacao inativa nao pode aparecer';
  end if;
  select count(*) into v_n from public.listar_eventos_publicos_organizacao(v_sb);
  if v_n <> 0 then raise exception 'T6: casa inativa nao pode listar eventos'; end if;
  update public.organizacoes set ativo = true where id = v_org_b;

  -- T7) resolver de links antigos: ambiguo -> null; unico -> casa ---------------
  if public.resolver_evento_publico('pagode-sexta') is not null then
    raise exception 'T7: slug presente em 2 casas deveria ser ambiguo';
  end if;
  update public.eventos set publicacao_status = 'RASCUNHO' where id = v_ev_b;
  v_res := public.resolver_evento_publico('pagode-sexta');
  if v_res->>'organizacao_slug' <> v_sa or v_res->>'evento_slug' <> 'pagode-sexta' then
    raise exception 'T7: deveria resolver para a casa A: %', v_res;
  end if;
  if public.resolver_evento_publico('nao-existe-xyz') is not null then
    raise exception 'T7: slug inexistente deveria resolver null';
  end if;

  -- T8) checkout devolve dados da organizacao ---------------------------------
  v_res := public.criar_reserva(v_ev_a, 'Comprador', '11999990000', 'c@test.local', array['Ana']);
  v_res := public.obter_checkout_pedido((v_res->>'checkout_token')::uuid);
  if v_res->>'organizacao_slug' <> v_sa or v_res->>'organizacao_nome' <> 'Casa A'
     or v_res->>'organizacao_logo_url' <> 'https://exemplo.com/logo.png' then
    raise exception 'T8: checkout sem dados da organizacao: %', v_res;
  end if;
end $$;

rollback;
