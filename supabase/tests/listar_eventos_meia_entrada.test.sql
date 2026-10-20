-- =============================================================================
-- Ingressoudi - Testes: listar_eventos_admin_filtrado devolve meia_entrada_ativa
-- (cartao do evento mostra inteira e meia). Executar como owner. begin/rollback.
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
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org Teste', 'org-teste-' || replace(gen_random_uuid()::text, '-', ''), 0)
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
declare
  v_admin uuid := gen_random_uuid();
  v_com uuid := gen_random_uuid();
  v_sem uuid := gen_random_uuid();
  v_lista jsonb;
  v_item jsonb;
begin
  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status, meia_entrada_ativa) values
    (v_com, 'Evento Com Meia', 'evento-meia-' || replace(v_com::text,'-',''), now() + interval '30 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO', true),
    (v_sem, 'Evento Sem Meia', 'evento-smeia-' || replace(v_sem::text,'-',''), now() + interval '31 days', 'Galeria', 'Rua 1', 100, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO', false);

  insert into auth.users (id) values (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Meia', 'adminmeia_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_lista := public.listar_eventos_admin_filtrado();

  select x into v_item from jsonb_array_elements(v_lista) x where x->>'evento_id' = v_com::text;
  if v_item is null then raise exception 'A: evento com meia ausente da lista'; end if;
  if (v_item->>'meia_entrada_ativa')::boolean is distinct from true then raise exception 'A: meia_entrada_ativa deveria ser true (%)', v_item; end if;

  select x into v_item from jsonb_array_elements(v_lista) x where x->>'evento_id' = v_sem::text;
  if v_item is null then raise exception 'B: evento sem meia ausente da lista'; end if;
  if (v_item->>'meia_entrada_ativa')::boolean is distinct from false then raise exception 'B: meia_entrada_ativa deveria ser false (%)', v_item; end if;
end $$;

select 'listar_eventos_meia_entrada: todos os testes passaram' as resultado;

rollback;
