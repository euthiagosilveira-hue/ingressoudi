-- =============================================================================
-- Ingressoudi - Testes: cadastro do produtor com aprovacao (Fase 3B parte 2)
-- Arquivo: supabase/tests/cadastro_produtor.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.concluir_cadastro_produtor(text,text,text,text)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode concluir cadastro';
  end if;
  if has_function_privilege('anon', 'public.listar_organizacoes_plataforma()', 'EXECUTE')
     or has_function_privilege('anon', 'public.definir_aprovacao_organizacao(uuid,boolean)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode administrar a plataforma';
  end if;
  if not has_function_privilege('anon', 'public.slug_organizacao_disponivel(text)', 'EXECUTE') then
    raise exception 'ACL: formulario de cadastro precisa checar o endereco';
  end if;
end $$;

do $$
declare
  v_prod uuid := gen_random_uuid();
  v_outro uuid := gen_random_uuid();
  v_super uuid := gen_random_uuid();
  v_slug text := 'cad-' || substr(replace(gen_random_uuid()::text,'-',''), 1, 10);
  v_res jsonb; v_org uuid; v_ev uuid; v_lista jsonb; v_n int;
begin
  insert into auth.users (id, email) values
    (v_prod, 'prod_' || replace(v_prod::text,'-','') || '@test.local'),
    (v_outro, 'outro_' || replace(v_outro::text,'-','') || '@test.local'),
    (v_super, 'super_' || replace(v_super::text,'-','') || '@test.local');
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'super_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true);

  -- T1) endereco disponivel / reservado / invalido -------------------------------
  if not public.slug_organizacao_disponivel(v_slug) then raise exception 'T1: slug livre deveria estar disponivel'; end if;
  if public.slug_organizacao_disponivel('painel') then raise exception 'T1: slug reservado'; end if;
  if public.slug_organizacao_disponivel('Com Espaco') then raise exception 'T1: slug invalido'; end if;

  -- T2) sem login nao conclui -------------------------------------------------
  begin
    perform public.concluir_cadastro_produtor('Prod', 'Casa Nova', v_slug, 'v1');
    raise exception 'T2: sem login deveria falhar';
  exception when others then
    if position('login' in lower(sqlerrm)) = 0 then raise exception 'T2: %', sqlerrm; end if;
  end;

  -- T3) sem aceite dos termos nao conclui ---------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_prod::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_prod::text, true);
  begin
    perform public.concluir_cadastro_produtor('Prod', 'Casa Nova', v_slug, null);
    raise exception 'T3: sem termos deveria falhar';
  exception when others then
    if position('termos' in lower(sqlerrm)) = 0 then raise exception 'T3: %', sqlerrm; end if;
  end;

  -- T4) cadastro cria perfil + casa EM ANALISE + vinculo admin + aceite -----------
  v_res := public.concluir_cadastro_produtor('Produtor Novo', 'Casa Nova', v_slug, 'v1-2026-10');
  v_org := (v_res->>'organizacao_id')::uuid;
  if (select aprovada from public.organizacoes where id = v_org) then raise exception 'T4: casa nova deveria estar em analise'; end if;
  if (select slug from public.organizacoes where id = v_org) <> v_slug then raise exception 'T4: slug incorreto'; end if;
  if not exists (select 1 from public.membros_organizacao where organizacao_id = v_org and usuario_id = v_prod and perfil = 'ADMINISTRADOR' and ativo) then
    raise exception 'T4: produtor deveria ser ADMINISTRADOR da casa';
  end if;
  if (select termos_versao from public.usuarios where id = v_prod) <> 'v1-2026-10'
     or (select termos_aceitos_em from public.usuarios where id = v_prod) is null then
    raise exception 'T4: aceite dos termos nao registrado';
  end if;
  if (public.obter_sessao_operador()->'organizacao'->>'aprovada')::boolean is not false then
    raise exception 'T4: sessao deveria indicar casa em analise';
  end if;

  -- T5) idempotente: repetir devolve a mesma casa --------------------------------
  v_res := public.concluir_cadastro_produtor('Produtor Novo', 'Outra Casa', 'outra-' || v_slug, 'v1-2026-10');
  if (v_res->>'organizacao_id')::uuid <> v_org or (v_res->>'ja_existente')::boolean is not true then
    raise exception 'T5: deveria devolver a casa existente: %', v_res;
  end if;
  select count(*) into v_n from public.organizacoes where slug = 'outra-' || v_slug;
  if v_n <> 0 then raise exception 'T5: nao deveria criar segunda casa'; end if;

  -- T6) casa em analise cria evento em rascunho, mas nao publica ------------------
  v_res := public.criar_evento_admin('Show Novo', 'show-novo', null, null,
                                     now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'RASCUNHO', 'ENCERRADAS');
  v_ev := (v_res->>'evento_id')::uuid;
  begin
    perform public.atualizar_evento_admin(v_ev, 'Show Novo', 'show-novo', null, null,
                                          now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', null);
    raise exception 'T6: casa em analise nao deveria publicar';
  exception when others then
    if position('em analise' in lower(sqlerrm)) = 0 then raise exception 'T6: %', sqlerrm; end if;
  end;
  begin
    perform public.criar_evento_admin('Show Pub', 'show-pub', null, null,
                                      now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', 'ABERTAS');
    raise exception 'T6: casa em analise nao deveria criar evento publicado';
  exception when others then
    if position('em analise' in lower(sqlerrm)) = 0 then raise exception 'T6 criar: %', sqlerrm; end if;
  end;

  -- T7) casa em analise nao aparece publicamente --------------------------------
  if public.obter_organizacao_publica(v_slug) is not null then
    raise exception 'T7: casa em analise nao deveria ter pagina publica';
  end if;

  -- T8) produtor nao aprova a propria casa nem lista a plataforma ----------------
  begin
    perform public.definir_aprovacao_organizacao(v_org, true);
    raise exception 'T8: produtor nao pode se aprovar';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'T8: %', sqlerrm; end if;
  end;
  begin
    perform public.listar_organizacoes_plataforma();
    raise exception 'T8: produtor nao pode listar a plataforma';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'T8 listar: %', sqlerrm; end if;
  end;

  -- T9) outro usuario nao reaproveita o mesmo endereco --------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_outro::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_outro::text, true);
  begin
    perform public.concluir_cadastro_produtor('Outro', 'Copia', v_slug, 'v1-2026-10');
    raise exception 'T9: endereco repetido deveria falhar';
  exception when others then
    if position('ja existe' in lower(sqlerrm)) = 0 then raise exception 'T9: %', sqlerrm; end if;
  end;
  begin
    perform public.concluir_cadastro_produtor('Outro', 'Painel', 'painel', 'v1-2026-10');
    raise exception 'T9: endereco reservado deveria falhar';
  exception when others then
    if position('indisponivel' in lower(sqlerrm)) = 0 then raise exception 'T9 reservado: %', sqlerrm; end if;
  end;

  -- T10) super admin lista e aprova; casa passa a publicar e aparecer ------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_lista := public.listar_organizacoes_plataforma();
  if not exists (
    select 1 from jsonb_array_elements(v_lista) x
     where (x->>'organizacao_id')::uuid = v_org and (x->>'aprovada')::boolean = false
       and x->>'administradores' like 'prod_%'
  ) then
    raise exception 'T10: lista da plataforma sem a casa pendente';
  end if;
  perform public.definir_aprovacao_organizacao(v_org, true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_prod::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_prod::text, true);
  perform public.atualizar_evento_admin(v_ev, 'Show Novo', 'show-novo', null, null,
                                        now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', null);
  if (select publicacao_status from public.eventos where id = v_ev) <> 'PUBLICADO' then
    raise exception 'T10: casa aprovada deveria publicar';
  end if;
  if public.obter_organizacao_publica(v_slug) is null then
    raise exception 'T10: casa aprovada deveria ter pagina publica';
  end if;
end $$;

rollback;
