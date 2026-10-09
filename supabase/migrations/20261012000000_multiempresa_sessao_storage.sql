-- =============================================================================
-- Ingressoudi - Multiempresa: sessao do operador, troca de organizacao,
-- criacao de organizacoes (super admin) e Storage por organizacao (Etapa D)
-- Migration: multiempresa_sessao_storage
-- =============================================================================

-- 1) SESSAO DO OPERADOR -----------------------------------------------------------
-- Retorna o usuario autenticado, o perfil NA ORGANIZACAO ATIVA e a lista de
-- organizacoes em que ele e membro ativo. Se a organizacao ativa estiver
-- invalida (membro/organizacao inativos) e houver outra valida, troca para ela.
create or replace function private.obter_sessao_operador()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_usuario public.usuarios%rowtype;
  v_org uuid;
  v_perfil public.perfil_usuario;
  v_org_json jsonb;
  v_lista jsonb;
begin
  if v_uid is null then
    return null;
  end if;

  select * into v_usuario from public.usuarios u where u.id = v_uid;
  if not found then
    return null;
  end if;

  v_org := private.organizacao_atual_id();

  if v_org is null and v_usuario.ativo then
    select m.organizacao_id into v_org
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
     where m.usuario_id = v_uid and m.ativo = true
     order by o.nome
     limit 1;
    if v_org is not null then
      update public.usuarios set organizacao_ativa_id = v_org where id = v_uid;
    end if;
  end if;

  if v_org is not null then
    select m.perfil, jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug)
      into v_perfil, v_org_json
      from public.membros_organizacao m
      join public.organizacoes o on o.id = m.organizacao_id
     where m.organizacao_id = v_org and m.usuario_id = v_uid;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome, 'slug', o.slug, 'perfil', m.perfil) order by o.nome), '[]'::jsonb)
    into v_lista
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
   where m.usuario_id = v_uid and m.ativo = true;

  return jsonb_build_object(
    'id', v_usuario.id,
    'nome', v_usuario.nome,
    'email', v_usuario.email,
    'perfil', v_perfil,
    'ativo', (v_usuario.ativo and v_perfil is not null),
    'super_admin', v_usuario.super_admin,
    'organizacao', v_org_json,
    'organizacoes', v_lista
  );
end;
$$;

create or replace function public.obter_sessao_operador()
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.obter_sessao_operador();
$$;

-- 2) TROCAR A ORGANIZACAO ATIVA --------------------------------------------------
create or replace function private.definir_organizacao_ativa(p_organizacao_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfil_usuario;
begin
  if v_uid is null then
    raise exception 'Permissao negada' using errcode = '42501';
  end if;

  select m.perfil into v_perfil
    from public.membros_organizacao m
    join public.organizacoes o on o.id = m.organizacao_id and o.ativo = true
    join public.usuarios u on u.id = m.usuario_id and u.ativo = true
   where m.organizacao_id = p_organizacao_id
     and m.usuario_id = v_uid
     and m.ativo = true;

  if v_perfil is null then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;

  -- usuarios.perfil acompanha a organizacao ativa (compatibilidade com o front)
  update public.usuarios
     set organizacao_ativa_id = p_organizacao_id,
         perfil = v_perfil
   where id = v_uid;

  return private.obter_sessao_operador();
end;
$$;

create or replace function public.definir_organizacao_ativa(p_organizacao_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.definir_organizacao_ativa(p_organizacao_id);
$$;

-- 3) CRIAR ORGANIZACAO (super admin da plataforma) --------------------------------
-- O super admin cria a organizacao, vira ADMINISTRADOR dela e passa a opera-la;
-- depois convida a equipe do produtor pela tela de usuarios.
create or replace function private.criar_organizacao(p_nome text, p_slug text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_slug text;
  v_id uuid;
begin
  if v_uid is null or not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome da organizacao' using errcode = '23514';
  end if;

  v_slug := btrim(
    regexp_replace(
      lower(
        translate(
          btrim(coalesce(nullif(btrim(p_slug), ''), p_nome)),
          U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00F1',
          'aaaaaeeeeiiiiooooouuuucn'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
  if v_slug = '' then
    raise exception 'Informe o slug da organizacao' using errcode = '23514';
  end if;

  begin
    insert into public.organizacoes (nome, slug) values (btrim(p_nome), v_slug) returning id into v_id;
  exception when unique_violation then
    raise exception 'Ja existe uma organizacao com esse endereco' using errcode = '23505';
  end;

  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil)
  values (v_id, v_uid, 'ADMINISTRADOR');

  update public.usuarios set organizacao_ativa_id = v_id, perfil = 'ADMINISTRADOR' where id = v_uid;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (v_uid, 'ORGANIZACAO_CRIADA', 'organizacoes', v_id, jsonb_build_object('nome', btrim(p_nome), 'slug', v_slug), v_id);

  return jsonb_build_object('organizacao_id', v_id, 'nome', btrim(p_nome), 'slug', v_slug);
end;
$$;

create or replace function public.criar_organizacao(p_nome text, p_slug text default null)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.criar_organizacao(p_nome, p_slug);
$$;

-- 4) PERMISSOES ------------------------------------------------------------------
revoke all on function private.obter_sessao_operador() from public, anon;
revoke all on function private.definir_organizacao_ativa(uuid) from public, anon;
revoke all on function private.criar_organizacao(text, text) from public, anon;
grant execute on function private.obter_sessao_operador() to authenticated, service_role;
grant execute on function private.definir_organizacao_ativa(uuid) to authenticated, service_role;
grant execute on function private.criar_organizacao(text, text) to authenticated, service_role;

revoke all on function public.obter_sessao_operador() from public, anon;
revoke all on function public.definir_organizacao_ativa(uuid) from public, anon;
revoke all on function public.criar_organizacao(text, text) from public, anon;
grant execute on function public.obter_sessao_operador() to authenticated, service_role;
grant execute on function public.definir_organizacao_ativa(uuid) to authenticated, service_role;
grant execute on function public.criar_organizacao(text, text) to authenticated, service_role;

-- usado pelas policies de Storage (executadas como o usuario autenticado)
grant execute on function private.organizacao_atual_id() to authenticated;

-- 5) STORAGE: capas na pasta da organizacao --------------------------------------
-- Caminho obrigatorio para escrita: {organizacao_id}/{arquivo}. Leitura continua publica.
drop policy if exists "eventos_capas_insert_admin" on storage.objects;
create policy "eventos_capas_insert_admin" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'eventos-capas'
    and private.usuario_e_admin()
    and (storage.foldername(name))[1] = private.organizacao_atual_id()::text
  );

drop policy if exists "eventos_capas_update_admin" on storage.objects;
create policy "eventos_capas_update_admin" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'eventos-capas'
    and private.usuario_e_admin()
    and (storage.foldername(name))[1] = private.organizacao_atual_id()::text
  )
  with check (
    bucket_id = 'eventos-capas'
    and private.usuario_e_admin()
    and (storage.foldername(name))[1] = private.organizacao_atual_id()::text
  );

drop policy if exists "eventos_capas_delete_admin" on storage.objects;
create policy "eventos_capas_delete_admin" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'eventos-capas'
    and private.usuario_e_admin()
    and (storage.foldername(name))[1] = private.organizacao_atual_id()::text
  );
