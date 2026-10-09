-- =============================================================================
-- GZ1 Ingresso - Testes: criar_evento_admin
-- Arquivo: supabase/tests/criar_evento_admin.test.sql
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.criar_evento_admin(text, text, text, text, timestamptz, text, text, integer, integer, public.status_publicacao, public.status_vendas)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar criar_evento_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_res jsonb;
  v_eid uuid;
  v_publicado_em timestamptz;
  v_status public.status_evento;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Ev', 'adminevc_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Ev', 'portevc_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.criar_evento_admin('X','x','',NULL, now()+interval '1 day','L','E',10,0,'RASCUNHO'::public.status_publicacao,'ENCERRADAS'::public.status_vendas);
    raise exception 'B: PORTARIA nao deveria criar evento';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B: inesperado: %', sqlerrm; end if;
  end;

  -- C) ADMIN cria (PUBLICADO)
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.criar_evento_admin(
    'Meu Evento Show', 'Meu Evento Show!', 'desc', NULL,
    now() + interval '10 days', 'Galeria', 'Rua 1',
    100, 50, 'PUBLICADO'::public.status_publicacao, 'ABERTAS'::public.status_vendas);
  v_eid := (v_res->>'evento_id')::uuid;
  if v_eid is null then raise exception 'C/K: evento_id ausente'; end if;

  -- D) status inicial
  if (v_res->>'status') <> 'AGENDADO' then raise exception 'D: status deveria ser AGENDADO'; end if;

  -- E) slug normalizado
  if (v_res->>'slug') <> 'meu-evento-show' then raise exception 'E: slug incorreto (%)', v_res->>'slug'; end if;

  -- I) PUBLICADO => publicado_em preenchido
  select status, publicado_em into v_status, v_publicado_em from public.eventos where id = v_eid;
  if v_publicado_em is null then raise exception 'I: publicado_em deveria estar preenchido'; end if;
  if v_status <> 'AGENDADO' then raise exception 'D: status persistido incorreto'; end if;

  -- F) slug duplicado => erro controlado
  begin
    perform public.criar_evento_admin(
      'Outro','Meu Evento Show!','',NULL, now()+interval '5 days','L','E',10,0,
      'RASCUNHO'::public.status_publicacao,'ENCERRADAS'::public.status_vendas);
    raise exception 'F: slug duplicado deveria falhar';
  exception when others then
    if position('endereco de url' in lower(sqlerrm)) = 0 then raise exception 'F: inesperado: %', sqlerrm; end if;
  end;

  -- J) RASCUNHO => publicado_em null
  v_res := public.criar_evento_admin(
    'Rascunho X','rascunho-x-'||replace(gen_random_uuid()::text,'-',''),'',NULL,
    now()+interval '5 days','L','E',10,0,'RASCUNHO'::public.status_publicacao,'ENCERRADAS'::public.status_vendas);
  select publicado_em into v_publicado_em from public.eventos where id = (v_res->>'evento_id')::uuid;
  if v_publicado_em is not null then raise exception 'J: RASCUNHO deveria ter publicado_em null'; end if;

  -- G) capacidade invalida
  begin
    perform public.criar_evento_admin('Cap','cap-'||replace(gen_random_uuid()::text,'-',''),'',NULL, now()+interval '1 day','L','E',0,0,'RASCUNHO'::public.status_publicacao,'ENCERRADAS'::public.status_vendas);
    raise exception 'G: capacidade 0 deveria falhar';
  exception when others then
    if position('capacidade' in lower(sqlerrm)) = 0 then raise exception 'G: inesperado: %', sqlerrm; end if;
  end;

  -- H) estoque > capacidade
  begin
    perform public.criar_evento_admin('Est','est-'||replace(gen_random_uuid()::text,'-',''),'',NULL, now()+interval '1 day','L','E',10,20,'RASCUNHO'::public.status_publicacao,'ENCERRADAS'::public.status_vendas);
    raise exception 'H: estoque>capacidade deveria falhar';
  exception when others then
    if position('exceder' in lower(sqlerrm)) = 0 then raise exception 'H: inesperado: %', sqlerrm; end if;
  end;
end $$;

select 'criar_evento_admin: todos os testes passaram' as resultado;

rollback;

