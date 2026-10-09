-- =============================================================================
-- GZ1 Ingresso - Testes: listar_eventos_admin_filtrado
-- Arquivo: supabase/tests/eventos_admin.test.sql
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
begin
  if has_function_privilege('anon', 'public.listar_eventos_admin_filtrado(text, public.status_evento, public.status_publicacao, public.status_vendas)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_eventos_admin_filtrado';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_ag uuid; v_ea uuid; v_re uuid; v_ca uuid;
  v_res jsonb;
  v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Ev', 'adminev_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Ev', 'portev_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Alfa Agendado','adm-alfa-'||replace(gen_random_uuid()::text,'-',''), now() + interval '3 days','Sala Alfa','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_ag;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Beta Andamento','adm-beta-'||replace(gen_random_uuid()::text,'-',''), now() - interval '1 hour','Sala Beta','E',100,50,'EM_ANDAMENTO','PUBLICADO','ENCERRADAS')
  returning id into v_ea;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Gama Realizado','adm-gama-'||replace(gen_random_uuid()::text,'-',''), now() - interval '10 days','Sala Gama','E',100,50,'REALIZADO','RASCUNHO','ENCERRADAS')
  returning id into v_re;
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Delta Cancelado','adm-delta-'||replace(gen_random_uuid()::text,'-',''), now() - interval '5 days','Espaco Delta','E',100,50,'CANCELADO','PUBLICADO','ENCERRADAS')
  returning id into v_ca;

  -- B) PORTARIA => negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.listar_eventos_admin_filtrado();
    raise exception 'B: PORTARIA nao deveria listar eventos admin';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then
      raise exception 'B: erro inesperado: %', sqlerrm;
    end if;
  end;

  -- C) ADMINISTRADOR => permitido; E) contem EM_ANDAMENTO
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.listar_eventos_admin_filtrado();
  if jsonb_typeof(v_res) <> 'array' or jsonb_array_length(v_res) < 4 then
    raise exception 'C: admin deveria listar os eventos';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_res) e where (e->>'evento_id')::uuid = v_ea) then
    raise exception 'E: EM_ANDAMENTO deveria aparecer';
  end if;
  -- ordenacao: EM_ANDAMENTO primeiro (grupo)
  if (v_res->0->>'status') <> 'EM_ANDAMENTO' then
    raise exception 'ordenacao: EM_ANDAMENTO deveria vir primeiro (obtido %)', v_res->0->>'status';
  end if;

  -- D) filtro status AGENDADO
  v_res := public.listar_eventos_admin_filtrado(p_busca => 'adm-alfa', p_status => 'AGENDADO'::public.status_evento);
  if jsonb_array_length(v_res) <> 1 or (v_res->0->>'evento_id')::uuid <> v_ag then
    raise exception 'D: filtro AGENDADO incorreto';
  end if;

  -- F) filtros publicacao RASCUNHO + vendas ENCERRADAS
  v_res := public.listar_eventos_admin_filtrado(
    p_publicacao => 'RASCUNHO'::public.status_publicacao,
    p_vendas => 'ENCERRADAS'::public.status_vendas);
  if not exists (select 1 from jsonb_array_elements(v_res) e where (e->>'evento_id')::uuid = v_re) then
    raise exception 'F: filtros publicacao/vendas incorretos';
  end if;

  -- G) busca por nome
  v_res := public.listar_eventos_admin_filtrado(p_busca => 'adm-beta');
  if jsonb_array_length(v_res) <> 1 or (v_res->0->>'evento_id')::uuid <> v_ea then
    raise exception 'G: busca por nome falhou';
  end if;

  -- H) busca por local
  v_res := public.listar_eventos_admin_filtrado(p_busca => 'Espaco Delta');
  if jsonb_array_length(v_res) <> 1 or (v_res->0->>'evento_id')::uuid <> v_ca then
    raise exception 'H: busca por local falhou';
  end if;

  -- I) busca inexistente
  v_res := public.listar_eventos_admin_filtrado(p_busca => 'zzz-nao-existe-zzz');
  if jsonb_array_length(v_res) <> 0 then
    raise exception 'I: busca inexistente deveria retornar vazio';
  end if;
end $$;

select 'eventos_admin: todos os testes passaram' as resultado;

rollback;
