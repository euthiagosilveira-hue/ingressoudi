-- =============================================================================
-- GZ1 Ingresso - Testes: gerenciamento de usuarios
-- Arquivo: supabase/tests/usuarios_admin.test.sql
-- Executar como owner. begin/rollback.
--
-- A) anon nao lista
-- B) PORTARIA nao lista
-- C) ADMIN lista
-- D) ADMIN atualiza usuario
-- E) nome vazio rejeitado
-- F) perfil invalido rejeitado
-- G) auto-desativacao rejeitada
-- H) ultimo ADMIN nao pode ser desativado
-- I) ultimo ADMIN nao pode virar PORTARIA
-- J) com 2 admins, 1 pode ser desativado
-- K) PORTARIA pode ser ativado/desativado por ADMIN
-- L) auditoria criada
-- =============================================================================

begin;

-- [Ingressoudi] Fixture multiempresa (Etapa A) ---------------------------------
-- Cria uma organizacao de teste; eventos inseridos sem organizacao caem nela e
-- todo usuario criado (ou com perfil alterado) vira membro dela com o mesmo
-- perfil. Tudo e desfeito pelo rollback ao final do arquivo.
do $fx$
declare
  v_org uuid;
begin
  insert into public.organizacoes (nome, slug)
  values ('Org Teste', 'org-teste-' || replace(gen_random_uuid()::text, '-', ''))
  returning id into v_org;
  execute format('alter table public.eventos alter column organizacao_id set default %L::uuid', v_org);
  perform set_config('teste.organizacao_id', v_org::text, true);
end
$fx$;

create function private.teste_vincular_membro()
returns trigger
language plpgsql
set search_path = ''
as $fx$
begin
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil, ativo)
  values (current_setting('teste.organizacao_id')::uuid, new.id, new.perfil, true)
  on conflict (organizacao_id, usuario_id) do update set perfil = excluded.perfil;
  return new;
end
$fx$;

create trigger trg_teste_vincular_membro
  after insert or update of perfil on public.usuarios
  for each row execute function private.teste_vincular_membro();
-- [/Ingressoudi] ------------------------------------------------------------------

do $$
begin
  if has_function_privilege('anon', 'public.listar_usuarios_admin(text)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_usuarios_admin';
  end if;
  if has_function_privilege('anon', 'public.atualizar_usuario_admin(uuid, text, public.perfil_usuario, boolean)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar atualizar_usuario_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_admin2 uuid := gen_random_uuid();
  v_port uuid := gen_random_uuid();
  v_lista jsonb;
  v_aud integer;
begin
  insert into auth.users (id) values (v_admin), (v_admin2), (v_port);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Usuarios', 'adminusu_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_admin2, 'Admin Usuarios 2', 'adminusu2_' || replace(v_admin2::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_port, 'Portaria Usuarios', 'portusu_' || replace(v_port::text,'-','') || '@test.local', 'PORTARIA', true);

  -- neutraliza outros admins ativos para os testes de "ultimo admin"
  update public.usuarios
     set ativo = false
   where perfil = 'ADMINISTRADOR'
     and ativo = true
     and id not in (v_admin, v_admin2);

  -- B) PORTARIA nao lista
  perform set_config('request.jwt.claims', json_build_object('sub', v_port::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_port::text, true);
  begin
    perform public.listar_usuarios_admin();
    raise exception 'B: PORTARIA nao deveria listar usuarios';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN lista
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_lista := public.listar_usuarios_admin();
  if jsonb_array_length(v_lista) < 3 then
    raise exception 'C: esperado ao menos 3 usuarios, obtido %', jsonb_array_length(v_lista);
  end if;

  -- D) ADMIN atualiza usuario (nome)
  perform public.atualizar_usuario_admin(v_port, 'Portaria Renomeada', 'PORTARIA', true);
  if (select nome from public.usuarios where id = v_port) <> 'Portaria Renomeada' then
    raise exception 'D: nome nao atualizado';
  end if;

  -- E) nome vazio rejeitado
  begin
    perform public.atualizar_usuario_admin(v_port, '   ', 'PORTARIA', true);
    raise exception 'E: nome vazio deveria falhar';
  exception when others then
    if position('nome' in lower(sqlerrm)) = 0 then raise exception 'E: inesperado: %', sqlerrm; end if;
  end;

  -- F) perfil invalido rejeitado (cast enum)
  begin
    execute 'select public.atualizar_usuario_admin($1, $2, ''INVALIDO'', $3)'
      using v_port, 'Nome', true;
    raise exception 'F: perfil invalido deveria falhar';
  exception when others then
    if position('enum' in lower(sqlerrm)) = 0 and position('invalid input' in lower(sqlerrm)) = 0 then
      raise exception 'F: inesperado: %', sqlerrm;
    end if;
  end;

  -- G) auto-desativacao rejeitada
  begin
    perform public.atualizar_usuario_admin(v_admin, 'Admin Usuarios', 'ADMINISTRADOR', false);
    raise exception 'G: auto-desativacao deveria falhar';
  exception when others then
    if position('proprio' in lower(sqlerrm)) = 0 then raise exception 'G: inesperado: %', sqlerrm; end if;
  end;

  -- J) com 2 admins ativos, 1 pode ser desativado
  perform public.atualizar_usuario_admin(v_admin2, 'Admin Usuarios 2', 'ADMINISTRADOR', false);
  if (select m.ativo from public.membros_organizacao m where m.usuario_id = v_admin2 and m.organizacao_id = current_setting('teste.organizacao_id')::uuid) then
    raise exception 'J: admin2 deveria estar inativo';
  end if;

  -- H) ultimo ADMIN ativo nao pode ser desativado
  begin
    perform public.atualizar_usuario_admin(v_admin, 'Admin Usuarios', 'ADMINISTRADOR', false);
    raise exception 'H: ultimo admin nao deveria ser desativado';
  exception when others then
    if position('proprio' in lower(sqlerrm)) = 0
       and position('administrador' in lower(sqlerrm)) = 0 then
      raise exception 'H: inesperado: %', sqlerrm;
    end if;
  end;

  -- I) ultimo ADMIN ativo nao pode virar PORTARIA
  begin
    perform public.atualizar_usuario_admin(v_admin, 'Admin Usuarios', 'PORTARIA', true);
    raise exception 'I: ultimo admin nao deveria ser rebaixado';
  exception when others then
    if position('administrador ativo' in lower(sqlerrm)) = 0 then
      raise exception 'I: inesperado: %', sqlerrm;
    end if;
  end;

  -- K) PORTARIA pode ser desativado/ativado por ADMIN
  perform public.atualizar_usuario_admin(v_port, 'Portaria Renomeada', 'PORTARIA', false);
  if (select m.ativo from public.membros_organizacao m where m.usuario_id = v_port and m.organizacao_id = current_setting('teste.organizacao_id')::uuid) then
    raise exception 'K: portaria deveria estar inativo';
  end if;
  perform public.atualizar_usuario_admin(v_port, 'Portaria Renomeada', 'PORTARIA', true);
  if not (select m.ativo from public.membros_organizacao m where m.usuario_id = v_port and m.organizacao_id = current_setting('teste.organizacao_id')::uuid) then
    raise exception 'K: portaria deveria estar ativo';
  end if;

  -- L) auditoria criada
  select count(*) into v_aud
    from public.auditoria
   where entidade = 'usuarios'
     and entidade_id in (v_admin, v_admin2, v_port);
  if v_aud < 1 then
    raise exception 'L: nenhuma auditoria de usuario registrada';
  end if;
end $$;

select 'usuarios_admin: todos os testes passaram' as resultado;

rollback;
