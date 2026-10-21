-- =============================================================================
-- Ingressoudi - Testes: donos das casas (Plataforma, somente super admin)
-- Arquivo: supabase/tests/donos_plataforma.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.listar_donos_plataforma()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode listar os donos das casas';
  end if;
  if not has_function_privilege('authenticated', 'public.listar_donos_plataforma()', 'EXECUTE') then
    raise exception 'ACL: authenticated deveria executar (a regra fica na funcao)';
  end if;
end $$;

do $$
declare
  v_org_a uuid; v_org_b uuid;
  v_super uuid := gen_random_uuid();
  v_dono_a uuid := gen_random_uuid();
  v_socio_a uuid := gen_random_uuid();
  v_port_a uuid := gen_random_uuid();
  v_dono_b uuid := gen_random_uuid();
  v_lista jsonb; v_a jsonb; v_b jsonb;
begin
  insert into public.organizacoes (nome, slug) values ('Donos A', 'donos-a-' || substr(md5(random()::text),1,10)) returning id into v_org_a;
  insert into public.organizacoes (nome, slug) values ('Donos B', 'donos-b-' || substr(md5(random()::text),1,10)) returning id into v_org_b;

  insert into auth.users (id) values (v_super), (v_dono_a), (v_socio_a), (v_port_a), (v_dono_b);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin, termos_versao, termos_aceitos_em) values
    (v_super, 'Super', 'donos_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true, null, null),
    (v_dono_a, 'Dono A', 'donos_a_' || replace(v_dono_a::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, '2026-10', now()),
    (v_socio_a, 'Socio A', 'donos_sa_' || replace(v_socio_a::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, null, null),
    (v_port_a, 'Porteiro A', 'donos_pa_' || replace(v_port_a::text,'-','') || '@test.local', 'PORTARIA', true, false, null, null),
    (v_dono_b, 'Dono B', 'donos_b_' || replace(v_dono_b::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, null, null);

  -- Casa A: o socio entrou ANTES do dono, mas o dono e quem registrou a casa (auditoria)
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, criado_em) values
    (v_org_a, v_socio_a, 'ADMINISTRADOR', now() - interval '2 days'),
    (v_org_a, v_dono_a, 'ADMINISTRADOR', now() - interval '1 day'),
    (v_org_a, v_port_a, 'PORTARIA', now());
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, organizacao_id)
  values (v_dono_a, 'ORGANIZACAO_CADASTRADA', 'organizacoes', v_org_a, v_org_a);

  -- Casa B: sem registro de cadastro; dono = administrador ativo mais antigo.
  -- O dono B tambem e membro da casa A (conta em outras_casas).
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_b, v_dono_b, 'ADMINISTRADOR');
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org_a, v_dono_b, 'PORTARIA');
  update public.usuarios set organizacao_ativa_id = v_org_a where id in (v_dono_a, v_socio_a, v_port_a, v_dono_b);

  -- T1) administrador comum nao acessa ----------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_dono_a::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_dono_a::text, true);
  begin
    perform public.listar_donos_plataforma();
    raise exception 'T1: admin comum nao deveria acessar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  -- T2) super admin (sem ser membro de nenhuma das casas) ve as duas ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_lista := public.listar_donos_plataforma();
  select x into v_a from jsonb_array_elements(v_lista) x where x->>'organizacao_id' = v_org_a::text;
  select x into v_b from jsonb_array_elements(v_lista) x where x->>'organizacao_id' = v_org_b::text;
  if v_a is null or v_b is null then raise exception 'T2: casas ausentes: A=% B=%', v_a, v_b; end if;

  -- T3) dono da casa A vem da auditoria, com termos; socio fica em outros administradores
  if v_a->'dono'->>'usuario_id' <> v_dono_a::text then raise exception 'T3: dono A errado: %', v_a->'dono'; end if;
  if v_a->'dono'->>'termos_versao' <> '2026-10' or v_a->'dono'->>'termos_aceitos_em' is null then
    raise exception 'T3: termos do dono A: %', v_a->'dono';
  end if;
  if jsonb_array_length(v_a->'outros_administradores') <> 1
     or v_a->'outros_administradores'->0->>'nome' <> 'Socio A' then
    raise exception 'T3: outros administradores da casa A: %', v_a->'outros_administradores';
  end if;
  if (v_a->>'equipe')::int <> 4 then raise exception 'T3: equipe da casa A deveria ser 4 (%)', v_a->>'equipe'; end if;

  -- T4) casa B sem auditoria: dono = admin mais antigo; conta a outra casa dele ------
  if v_b->'dono'->>'usuario_id' <> v_dono_b::text then raise exception 'T4: dono B errado: %', v_b->'dono'; end if;
  if (v_b->'dono'->>'outras_casas')::int <> 1 then raise exception 'T4: outras_casas do dono B: %', v_b->'dono'; end if;
  if jsonb_array_length(v_b->'outros_administradores') <> 0 then raise exception 'T4: casa B nao tem outros admins: %', v_b; end if;
  if (v_b->>'mercado_pago_conectado')::boolean then raise exception 'T4: casa B sem Mercado Pago: %', v_b; end if;

  -- T5) nada sensivel do Mercado Pago sai na lista ------------------------------------
  if v_lista::text ilike '%token%' then raise exception 'T5: a lista nao pode trazer tokens'; end if;
end $$;

select 'donos_plataforma: todos os testes passaram' as resultado;

rollback;
