-- =============================================================================
-- Ingressoudi - Testes: encerrar lote manualmente pelo painel
-- (encerrar_lote_admin). Executar como owner. begin/rollback.
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
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_l1 uuid := gen_random_uuid();
  v_l2 uuid := gen_random_uuid();
  v_l3 uuid := gen_random_uuid();
  v_org_b uuid;
  v_evento_b uuid := gen_random_uuid();
  v_lote_b uuid := gen_random_uuid();
  v_res jsonb;
  v_status text;
  v_n integer;
begin
  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Encerrar Lote', 'evento-enc-' || replace(v_evento::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 1', 1000, 1000, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values
    (v_l1, v_evento, 'Lote 1', 1, 100, 30, 'MANUAL', 'ATIVO'),
    (v_l2, v_evento, 'Lote 2', 2, 100, 40, 'MANUAL', 'INATIVO'),
    (v_l3, v_evento, 'Lote 3', 3, 100, 50, 'MANUAL', 'INATIVO');

  -- Outra organizacao, com o proprio evento e lote
  insert into public.organizacoes (nome, slug, taxa_servico)
  values ('Org B', 'org-b-' || replace(gen_random_uuid()::text, '-', ''), 0)
  returning id into v_org_b;
  insert into public.eventos (id, organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento_b, v_org_b, 'Evento Org B', 'evento-encb-' || replace(v_evento_b::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 2', 1000, 1000, 'AGENDADO', 'ABERTAS', 'PUBLICADO');
  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote_b, v_evento_b, 'Lote B', 1, 100, 30, 'MANUAL', 'ATIVO');

  -- A) ACL: anon nao executa; authenticated executa (a regra fica na funcao)
  if has_function_privilege('anon', 'public.encerrar_lote_admin(uuid, boolean)', 'execute') then raise exception 'A: anon nao deveria executar'; end if;
  if not has_function_privilege('authenticated', 'public.encerrar_lote_admin(uuid, boolean)', 'execute') then raise exception 'A: authenticated deveria executar'; end if;

  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Enc', 'adminenc_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Portaria Enc', 'portenc_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  -- B) PORTARIA nao encerra lote
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.encerrar_lote_admin(v_l1, false);
    raise exception 'B: PORTARIA deveria ser recusada';
  exception when others then
    if position('Permissao negada' in sqlerrm) = 0 then raise exception 'B: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- C) lote de outra organizacao: nao encontrado e nada muda
  begin
    perform public.encerrar_lote_admin(v_lote_b, false);
    raise exception 'C: lote de outra organizacao deveria ser recusado';
  exception when others then
    if position('nao encontrado' in sqlerrm) = 0 then raise exception 'C: %', sqlerrm; end if;
  end;
  select status::text into v_status from public.lotes where id = v_lote_b;
  if v_status <> 'ATIVO' then raise exception 'C: lote da Org B nao deveria mudar (%)', v_status; end if;

  -- D) lote que nao esta ativo nao e encerrado
  begin
    perform public.encerrar_lote_admin(v_l2, false);
    raise exception 'D: lote INATIVO deveria ser recusado';
  exception when others then
    if position('nao esta ativo' in sqlerrm) = 0 then raise exception 'D: %', sqlerrm; end if;
  end;

  -- E) encerrar e ativar o proximo: Lote 1 ENCERRADO, Lote 2 ATIVO, Lote 3 segue INATIVO
  v_res := public.encerrar_lote_admin(v_l1, true);
  if v_res->>'resultado' <> 'ENCERRADO_E_PROXIMO_ATIVADO' then raise exception 'E: resultado inesperado (%)', v_res; end if;
  if (v_res->>'lote_ativado_id')::uuid <> v_l2 then raise exception 'E: deveria ativar o Lote 2 (%)', v_res; end if;
  select status::text into v_status from public.lotes where id = v_l1;
  if v_status <> 'ENCERRADO' then raise exception 'E: Lote 1 deveria estar ENCERRADO (%)', v_status; end if;
  select status::text into v_status from public.lotes where id = v_l2;
  if v_status <> 'ATIVO' then raise exception 'E: Lote 2 deveria estar ATIVO (%)', v_status; end if;
  select status::text into v_status from public.lotes where id = v_l3;
  if v_status <> 'INATIVO' then raise exception 'E: Lote 3 deveria seguir INATIVO (%)', v_status; end if;
  select count(*) into v_n from public.auditoria where acao = 'LOTE_ENCERRADO_MANUALMENTE' and entidade_id = v_l1;
  if v_n <> 1 then raise exception 'E: auditoria ausente (%)', v_n; end if;

  -- F) encerrar sem ativar o proximo: evento fica sem lote ativo
  v_res := public.encerrar_lote_admin(v_l2, false);
  if v_res->>'resultado' <> 'ENCERRADO' then raise exception 'F: resultado inesperado (%)', v_res; end if;
  select count(*) into v_n from public.lotes where evento_id = v_evento and status = 'ATIVO';
  if v_n <> 0 then raise exception 'F: nao deveria haver lote ativo (%)', v_n; end if;

  -- G) lote encerrado com ingressos pode ser reativado depois
  v_res := public.ativar_lote_manual(v_l2);
  if v_res->>'resultado' <> 'ATIVADO' then raise exception 'G: esperado ATIVADO (%)', v_res; end if;

  -- H) com vendas encerradas, so encerra (nao ativa o proximo)
  update public.eventos set vendas_status = 'ENCERRADAS' where id = v_evento;
  v_res := public.encerrar_lote_admin(v_l2, true);
  if v_res->>'resultado' <> 'ENCERRADO' then raise exception 'H: resultado inesperado (%)', v_res; end if;
  select status::text into v_status from public.lotes where id = v_l3;
  if v_status <> 'INATIVO' then raise exception 'H: Lote 3 deveria seguir INATIVO (%)', v_status; end if;
end $$;

select 'encerrar_lote_admin: todos os testes passaram' as resultado;

rollback;
