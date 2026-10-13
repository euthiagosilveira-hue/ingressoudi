-- =============================================================================
-- GZ1 Ingresso - Testes: autorizacao da portaria / eventos operacionais
-- Arquivo: supabase/tests/portaria_auth.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
--
-- Simula autenticacao via request.jwt.claims (auth.uid()).
-- Observacao: o enum public.perfil_usuario possui apenas ADMINISTRADOR e
-- PORTARIA; portanto nao existe caso "perfil existente nao permitido".
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

-- A) anon nao executa nenhuma RPC de portaria --------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.registrar_entrada_qr(uuid, text)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar registrar_entrada_qr';
  end if;
  if has_function_privilege('anon', 'public.listar_eventos_portaria()', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_eventos_portaria';
  end if;
  if has_function_privilege('anon', 'public.buscar_ingressos_por_nome(uuid, text)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar buscar_ingressos_por_nome';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_inativo uuid := gen_random_uuid();
  v_sem_usuario uuid := gen_random_uuid();
  v_evento uuid;
  v_res jsonb;
  v_lista jsonb;
begin
  insert into auth.users (id) values (v_admin), (v_portaria), (v_inativo);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Teste', 'admin_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Portaria Teste', 'port_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true),
    (v_inativo, 'Portaria Inativo', 'inativo_' || replace(v_inativo::text,'-','') || '@test.local', 'PORTARIA', false);

  insert into public.eventos (
    nome, slug, inicio_em, local, endereco,
    capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status
  ) values (
    'Evento Portaria Auth', 'portaria-auth-' || replace(gen_random_uuid()::text,'-',''),
    now() + interval '2 days', 'Local A', 'End A',
    100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS'
  ) returning id into v_evento;

  -- B) authenticated sem linha em public.usuarios => sem permissao -----------
  perform set_config('request.jwt.claims', json_build_object('sub', v_sem_usuario::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_sem_usuario::text, true);
  begin
    perform public.registrar_entrada_qr(v_evento, 'token-x');
    raise exception 'B: deveria negar sem usuario';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'B: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- C) perfil PORTARIA => permitido (token inexistente => NAO_ENCONTRADO) -----
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_res := public.registrar_entrada_qr(v_evento, 'token-inexistente');
  if (v_res->>'resultado') <> 'NAO_ENCONTRADO' then
    raise exception 'C: PORTARIA deveria ter permissao (obtido %)', v_res->>'resultado';
  end if;

  -- D) perfil ADMINISTRADOR => permitido -------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.registrar_entrada_qr(v_evento, 'token-inexistente');
  if (v_res->>'resultado') <> 'NAO_ENCONTRADO' then
    raise exception 'D: ADMINISTRADOR deveria ter permissao (obtido %)', v_res->>'resultado';
  end if;

  -- E) usuario inativo => sem permissao ---------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_inativo::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_inativo::text, true);
  begin
    perform public.registrar_entrada_qr(v_evento, 'token-x');
    raise exception 'E: deveria negar usuario inativo';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'E: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- F) listar_eventos_portaria: sem permissao para anonimo; ok para operador --
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.listar_eventos_portaria();
    raise exception 'F: deveria negar listar_eventos_portaria sem operador';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'F: erro inesperado: %', sqlerrm;
    end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_lista := public.listar_eventos_portaria();
  if jsonb_typeof(v_lista) <> 'array' then
    raise exception 'F: listar_eventos_portaria deveria retornar array';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_lista) as item
     where (item->>'evento_id')::uuid = v_evento
  ) then
    raise exception 'F: evento operacional deveria aparecer na lista';
  end if;
end $$;

select 'portaria_auth: todos os testes passaram' as resultado;

rollback;
