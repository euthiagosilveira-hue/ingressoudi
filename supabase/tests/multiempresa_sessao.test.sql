-- =============================================================================
-- Ingressoudi - Testes: sessao do operador, troca de organizacao, criacao de
-- organizacao e Storage por organizacao (Etapa D)
-- Arquivo: supabase/tests/multiempresa_sessao.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

-- ACL ------------------------------------------------------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.obter_sessao_operador()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode executar obter_sessao_operador'; end if;
  if has_function_privilege('anon', 'public.definir_organizacao_ativa(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode executar definir_organizacao_ativa'; end if;
  if has_function_privilege('anon', 'public.criar_organizacao(text, text)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode executar criar_organizacao'; end if;
end $$;

do $$
declare
  v_org_a uuid; v_org_b uuid; v_org_x uuid;
  v_super uuid := gen_random_uuid();
  v_multi uuid := gen_random_uuid();
  v_sem uuid := gen_random_uuid();
  v_res jsonb;
begin
  insert into public.organizacoes (nome, slug) values ('Alfa Shows', 'ses-a-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Beta Eventos', 'ses-b-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_b;
  insert into public.organizacoes (nome, slug) values ('Xis Fechada', 'ses-x-' || replace(gen_random_uuid()::text,'-','')) returning id into v_org_x;

  insert into auth.users (id) values (v_super), (v_multi), (v_sem);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'ses_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_multi, 'Multi', 'ses_m_' || replace(v_multi::text,'-','') || '@test.local', 'PORTARIA', true, false),
    (v_sem,   'Sem',   'ses_x_' || replace(v_sem::text,'-','')   || '@test.local', 'ADMINISTRADOR', true, false);

  -- multi: ADMIN em A, PORTARIA em B; ativa inicial = A (primeira associacao)
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org_a, v_multi, 'ADMINISTRADOR');
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org_b, v_multi, 'PORTARIA');

  -- S1) sessao: perfil e organizacao ativa ---------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_multi::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_multi::text, true);
  v_res := public.obter_sessao_operador();
  if v_res->>'perfil' <> 'ADMINISTRADOR' or (v_res->'organizacao'->>'id')::uuid <> v_org_a or (v_res->>'ativo')::boolean is not true then
    raise exception 'S1: sessao inicial incorreta: %', v_res; end if;
  if jsonb_array_length(v_res->'organizacoes') <> 2 then
    raise exception 'S1: deveria listar 2 organizacoes: %', v_res->'organizacoes'; end if;

  -- S2) troca para B: perfil vira PORTARIA e os helpers acompanham -------------------
  v_res := public.definir_organizacao_ativa(v_org_b);
  if v_res->>'perfil' <> 'PORTARIA' or (v_res->'organizacao'->>'id')::uuid <> v_org_b then
    raise exception 'S2: troca para B incorreta: %', v_res; end if;
  if private.usuario_e_admin() or not private.usuario_pode_operar_portaria() then
    raise exception 'S2: em B o usuario deveria ser apenas PORTARIA'; end if;
  if (select perfil from public.usuarios where id = v_multi) <> 'PORTARIA' then
    raise exception 'S2: usuarios.perfil deveria acompanhar a organizacao ativa'; end if;

  -- S3) nao pode trocar para organizacao da qual nao e membro -----------------------
  begin
    perform public.definir_organizacao_ativa(v_org_x);
    raise exception 'S3: troca para organizacao alheia deveria falhar';
  exception when others then
    if position('nao encontrada' in lower(sqlerrm)) = 0 then raise exception 'S3: erro inesperado: %', sqlerrm; end if;
  end;

  -- S4) membro desativado em B: sessao cai automaticamente para A ------------------
  update public.membros_organizacao set ativo = false where organizacao_id = v_org_b and usuario_id = v_multi;
  v_res := public.obter_sessao_operador();
  if (v_res->'organizacao'->>'id')::uuid <> v_org_a or v_res->>'perfil' <> 'ADMINISTRADOR' then
    raise exception 'S4: deveria voltar para a organizacao valida A: %', v_res; end if;
  if jsonb_array_length(v_res->'organizacoes') <> 1 then
    raise exception 'S4: deveria listar so 1 organizacao valida'; end if;

  -- S5) usuario sem nenhuma organizacao: sessao sem perfil e inativa ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_sem::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_sem::text, true);
  v_res := public.obter_sessao_operador();
  if v_res->>'perfil' is not null or (v_res->>'ativo')::boolean is not false or v_res->'organizacao' <> 'null'::jsonb then
    raise exception 'S5: usuario sem organizacao nao deveria ter perfil: %', v_res; end if;

  -- S6) somente super admin cria organizacao ----------------------------------------
  begin
    perform public.criar_organizacao('Hack', null);
    raise exception 'S6: usuario comum nao pode criar organizacao';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'S6: erro inesperado: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.criar_organizacao('Casa do Pagode São João', null);
  if v_res->>'slug' <> 'casa-do-pagode-sao-joao' then
    raise exception 'S6: slug gerado incorreto: %', v_res->>'slug'; end if;
  if private.organizacao_atual_id() <> (v_res->>'organizacao_id')::uuid or not private.usuario_e_admin() then
    raise exception 'S6: super admin deveria virar ADMINISTRADOR da nova organizacao'; end if;
  begin
    perform public.criar_organizacao('Outra', 'casa-do-pagode-sao-joao');
    raise exception 'S6: slug duplicado deveria falhar';
  exception when others then
    if position('ja existe' in lower(sqlerrm)) = 0 then raise exception 'S6: erro inesperado: %', sqlerrm; end if;
  end;

  -- S7) Storage: admin so grava na pasta da propria organizacao --------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_multi::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_multi::text, true);
  perform set_config('role', 'authenticated', true);
  insert into storage.objects (bucket_id, name) values ('eventos-capas', v_org_a::text || '/capa-teste.png');
  begin
    insert into storage.objects (bucket_id, name) values ('eventos-capas', v_org_b::text || '/capa-hack.png');
    raise exception 'S7: gravar na pasta de outra organizacao deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('eventos-capas', 'capas/sem-organizacao.png');
    raise exception 'S7: gravar fora da pasta da organizacao deveria falhar';
  exception when insufficient_privilege then null;
  end;
  perform set_config('role', 'postgres', true);
end $$;

select 'multiempresa_sessao: todos os testes passaram' as resultado;

rollback;
