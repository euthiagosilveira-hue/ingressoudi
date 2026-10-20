-- =============================================================================
-- Ingressoudi - Testes: Lista VIP liberada por organizacao (super admin)
-- Executar como owner. begin/rollback.
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
  -- taxa_servico 0: os testes herdados validam valores sem a taxa da plataforma
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
  v_org uuid := current_setting('teste.organizacao_id')::uuid;
  v_admin uuid := gen_random_uuid();
  v_super uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_res jsonb;
  v_ok boolean;
  v_n integer;
begin
  -- A) ACL
  if has_function_privilege('anon', 'public.definir_lista_vip_organizacao(uuid, boolean)', 'EXECUTE') then
    raise exception 'A: anon nao pode executar definir_lista_vip_organizacao'; end if;

  -- B) nova organizacao nasce com a Lista VIP desligada
  select lista_vip_ativa into v_ok from public.organizacoes where id = v_org;
  if v_ok then raise exception 'B: Lista VIP deveria nascer desligada'; end if;

  insert into auth.users (id) values (v_admin), (v_super);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_admin, 'Admin VIP', 'adminvip_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false),
    (v_super, 'Super VIP', 'supervip_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento VIP Org', 'evento-viporg-' || replace(v_evento::text,'-',''), now() + interval '20 days',
          'Galeria', 'Rua 1', 500, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  -- C) admin comum: sessao sem Lista VIP e inclusao recusada
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.obter_sessao_operador();
  if (v_res->'organizacao'->>'lista_vip')::boolean is distinct from false then
    raise exception 'C: sessao deveria indicar lista_vip=false (%)', v_res->'organizacao'; end if;
  begin
    perform public.criar_lista_vip_admin(v_evento, 'Convidado Bloqueado');
    raise exception 'C: inclusao deveria ser recusada';
  exception when others then
    if position('nao liberada' in sqlerrm) = 0 then raise exception 'C: %', sqlerrm; end if;
  end;

  -- D) admin comum nao libera a propria Lista VIP
  begin
    perform public.definir_lista_vip_organizacao(v_org, true);
    raise exception 'D: admin comum nao deveria liberar';
  exception when others then
    if position('super administrador' in sqlerrm) = 0 then raise exception 'D: %', sqlerrm; end if;
  end;

  -- E) super admin usa a Lista VIP mesmo desligada
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  perform public.criar_lista_vip_admin(v_evento, 'Convidado do Super');

  -- F) super admin libera para a organizacao; listagem e auditoria refletem
  v_res := public.definir_lista_vip_organizacao(v_org, true);
  if (v_res->>'lista_vip_ativa')::boolean is not true then raise exception 'F: retorno incorreto (%)', v_res; end if;
  select count(*) into v_n
    from jsonb_array_elements(public.listar_organizacoes_plataforma()) o
   where o->>'organizacao_id' = v_org::text and (o->>'lista_vip_ativa')::boolean;
  if v_n <> 1 then raise exception 'F: listagem deveria mostrar lista_vip_ativa'; end if;
  select count(*) into v_n from public.auditoria where acao = 'LISTA_VIP_LIBERADA' and entidade_id = v_org;
  if v_n <> 1 then raise exception 'F: auditoria ausente'; end if;

  -- G) liberada: admin comum inclui convidado e a sessao indica lista_vip=true
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_res := public.obter_sessao_operador();
  if (v_res->'organizacao'->>'lista_vip')::boolean is not true then
    raise exception 'G: sessao deveria indicar lista_vip=true'; end if;
  perform public.criar_lista_vip_admin(v_evento, 'Convidado Liberado');
  select count(*) into v_n from public.lista_vip where evento_id = v_evento;
  if v_n <> 2 then raise exception 'G: esperado 2 convidados (%)', v_n; end if;

  -- H) desligada de novo: inclusao volta a ser recusada
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  perform public.definir_lista_vip_organizacao(v_org, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.criar_lista_vip_admin(v_evento, 'Convidado Depois');
    raise exception 'H: inclusao deveria ser recusada';
  exception when others then
    if position('nao liberada' in sqlerrm) = 0 then raise exception 'H: %', sqlerrm; end if;
  end;
end $$;

select 'lista_vip_por_organizacao: todos os testes passaram' as resultado;

rollback;
