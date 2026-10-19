-- =============================================================================
-- Ingressoudi - Testes: convite de usuarios por link
-- Arquivo: supabase/tests/convite_por_link.test.sql
-- Executar como owner. begin/rollback.
--
-- A) anon e authenticated nao executam situacao_convite_usuario
-- B) listar_usuarios_admin informa pendente e ultimo_acesso_em do auth
-- C) situacao_convite_usuario: pendente, membro, outras organizacoes
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.situacao_convite_usuario(uuid, uuid)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar situacao_convite_usuario';
  end if;
  if has_function_privilege('authenticated', 'public.situacao_convite_usuario(uuid, uuid)', 'EXECUTE') then
    raise exception 'A: authenticated nao pode executar situacao_convite_usuario';
  end if;
  if has_function_privilege('authenticated', 'private.situacao_convite_usuario(uuid, uuid)', 'EXECUTE') then
    raise exception 'A: authenticated nao pode executar private.situacao_convite_usuario';
  end if;
  if not has_function_privilege('service_role', 'public.situacao_convite_usuario(uuid, uuid)', 'EXECUTE') then
    raise exception 'A: service_role deve executar situacao_convite_usuario';
  end if;
end $$;

do $$
declare
  v_org uuid;
  v_org2 uuid;
  v_admin uuid := gen_random_uuid();
  v_pend uuid := gen_random_uuid();
  v_lista jsonb;
  v_item jsonb;
  v_sit jsonb;
begin
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org Convite', 'org-convite-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org;
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org Convite 2', 'org-convite2-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org2;

  insert into auth.users (id, encrypted_password, last_sign_in_at, email_confirmed_at) values
    (v_admin, 'hash-qualquer', '2026-10-18 12:00:00+00', now()),
    (v_pend, null, null, null);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Convite', 'adminconv_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_pend, 'Pendente Convite', 'pendconv_' || replace(v_pend::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo) values
    (v_org, v_admin, 'ADMINISTRADOR', true),
    (v_org, v_pend, 'PORTARIA', true)
  on conflict (organizacao_id, usuario_id) do update set perfil = excluded.perfil, ativo = true;
  update public.usuarios set organizacao_ativa_id = v_org where id in (v_admin, v_pend);

  -- B) lista com pendente e ultimo acesso
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_lista := public.listar_usuarios_admin();

  select e into v_item from jsonb_array_elements(v_lista) e where e->>'id' = v_pend::text;
  if v_item is null then raise exception 'B: pendente ausente da lista'; end if;
  if (v_item->>'pendente')::boolean is distinct from true then
    raise exception 'B: usuario sem senha deveria estar pendente: %', v_item;
  end if;

  select e into v_item from jsonb_array_elements(v_lista) e where e->>'id' = v_admin::text;
  if (v_item->>'pendente')::boolean is distinct from false then
    raise exception 'B: usuario com senha nao deveria estar pendente: %', v_item;
  end if;
  if (v_item->>'ultimo_acesso_em')::timestamptz <> '2026-10-18 12:00:00+00'::timestamptz then
    raise exception 'B: ultimo_acesso_em deveria vir do auth: %', v_item;
  end if;

  -- C) situacao do convite
  v_sit := public.situacao_convite_usuario(v_pend, v_org);
  if not (v_sit->>'existe')::boolean or not (v_sit->>'membro')::boolean
     or not (v_sit->>'pendente')::boolean or (v_sit->>'email_confirmado')::boolean
     or (v_sit->>'outras_organizacoes')::int <> 0 then
    raise exception 'C: situacao inesperada (pendente): %', v_sit;
  end if;

  v_sit := public.situacao_convite_usuario(v_admin, v_org);
  if (v_sit->>'pendente')::boolean or not (v_sit->>'email_confirmado')::boolean then
    raise exception 'C: situacao inesperada (admin): %', v_sit;
  end if;

  v_sit := public.situacao_convite_usuario(v_pend, v_org2);
  if (v_sit->>'membro')::boolean or (v_sit->>'outras_organizacoes')::int <> 1 then
    raise exception 'C: situacao inesperada (outra org): %', v_sit;
  end if;

  v_sit := public.situacao_convite_usuario(gen_random_uuid(), v_org);
  if (v_sit->>'existe')::boolean or (v_sit->>'pendente')::boolean then
    raise exception 'C: usuario inexistente: %', v_sit;
  end if;
end $$;

rollback;
