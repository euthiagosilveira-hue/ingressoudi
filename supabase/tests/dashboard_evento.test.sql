-- =============================================================================
-- GZ1 Ingresso - Testes: evento relevante do dashboard
-- Arquivo: supabase/tests/dashboard_evento.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre a regra de selecao do card "Proximo evento":
--   A) EM_ANDAMENTO -> retorna ele
--   B) EM_ANDAMENTO + AGENDADO futuro -> retorna EM_ANDAMENTO
--   C) sem EM_ANDAMENTO + 1 AGENDADO futuro -> retorna o futuro
--   D) varios AGENDADOS futuros -> retorna o mais proximo
--   E) apenas REALIZADOS -> null
--   F) apenas CANCELADOS -> null
--   G) AGENDADO no passado -> nao retorna
--   H) imagem_url retornada corretamente
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
  if has_function_privilege('anon', 'public.obter_dashboard_admin()', 'EXECUTE') then
    raise exception 'ACL: anon nao pode executar obter_dashboard_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_and uuid;
  v_ag1 uuid;
  v_ag2 uuid;
  v_res jsonb;
  v_ev jsonb;
begin
  insert into auth.users (id) values (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo)
  values (v_admin, 'Admin Ev', 'adminev_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- neutraliza eventos pre-existentes para tornar a selecao deterministica
  update public.eventos set status = 'REALIZADO'
   where status in ('AGENDADO', 'EM_ANDAMENTO');

  -- A/H) apenas EM_ANDAMENTO, com capa real
  insert into public.eventos (nome, slug, imagem_url, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Ev Andamento', 'ev-and-'||replace(gen_random_uuid()::text,'-',''), 'https://cdn.exemplo.com/and.jpg', now() - interval '1 hour', 'L', 'E', 100, 50, 'EM_ANDAMENTO', 'PUBLICADO', 'ENCERRADAS')
  returning id into v_and;

  v_res := public.obter_dashboard_admin();
  v_ev := v_res->'evento';
  if (v_ev->>'evento_id')::uuid <> v_and then raise exception 'A: esperado EM_ANDAMENTO'; end if;
  if (v_ev->>'status') <> 'EM_ANDAMENTO' then raise exception 'A: status incorreto'; end if;

  -- H) capa real
  if (v_ev->>'imagem_url') <> 'https://cdn.exemplo.com/and.jpg' then
    raise exception 'H: imagem_url ausente/incorreta (obtido %)', v_ev->>'imagem_url';
  end if;

  -- B) EM_ANDAMENTO + AGENDADO futuro -> mantem EM_ANDAMENTO
  insert into public.eventos (nome, slug, imagem_url, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Ev Ag 1', 'ev-ag1-'||replace(gen_random_uuid()::text,'-',''), null, now() + interval '1 day', 'L', 'E', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ag1;

  v_res := public.obter_dashboard_admin();
  if (v_res->'evento'->>'evento_id')::uuid <> v_and then
    raise exception 'B: EM_ANDAMENTO deveria vencer o AGENDADO';
  end if;

  -- D) sem EM_ANDAMENTO, varios AGENDADOS futuros -> mais proximo (ag1 +1d < ag2 +3d)
  update public.eventos set status = 'REALIZADO' where id = v_and;
  insert into public.eventos (nome, slug, imagem_url, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Ev Ag 2', 'ev-ag2-'||replace(gen_random_uuid()::text,'-',''), null, now() + interval '3 days', 'L', 'E', 100, 50, 'AGENDADO', 'PUBLICADO', 'ABERTAS')
  returning id into v_ag2;

  v_res := public.obter_dashboard_admin();
  if (v_res->'evento'->>'evento_id')::uuid <> v_ag1 then
    raise exception 'D: deveria retornar o AGENDADO mais proximo';
  end if;

  -- G) AGENDADO no passado nao conta como proximo
  update public.eventos set status = 'REALIZADO' where id = v_ag2;
  update public.eventos set inicio_em = now() - interval '1 day' where id = v_ag1;
  v_res := public.obter_dashboard_admin();
  if coalesce(jsonb_typeof(v_res->'evento'), 'null') <> 'null' then
    raise exception 'G: AGENDADO no passado nao deveria aparecer';
  end if;

  -- C) um unico AGENDADO futuro -> retorna ele
  update public.eventos set inicio_em = now() + interval '2 days' where id = v_ag1;
  v_res := public.obter_dashboard_admin();
  if (v_res->'evento'->>'evento_id')::uuid <> v_ag1 then
    raise exception 'C: deveria retornar o unico AGENDADO futuro';
  end if;

  -- E) apenas REALIZADOS -> null
  update public.eventos set status = 'REALIZADO' where id = v_ag1;
  v_res := public.obter_dashboard_admin();
  if coalesce(jsonb_typeof(v_res->'evento'), 'null') <> 'null' then
    raise exception 'E: apenas REALIZADOS deveria ser null';
  end if;

  -- F) apenas CANCELADOS -> null
  update public.eventos set status = 'CANCELADO', inicio_em = now() + interval '5 days' where id = v_ag1;
  v_res := public.obter_dashboard_admin();
  if coalesce(jsonb_typeof(v_res->'evento'), 'null') <> 'null' then
    raise exception 'F: apenas CANCELADOS deveria ser null';
  end if;
end $$;

select 'dashboard_evento: todos os testes passaram' as resultado;

rollback;
