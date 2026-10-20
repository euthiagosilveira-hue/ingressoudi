-- =============================================================================
-- Ingressoudi - Testes: notificacao push para o super admin
-- (registrar_push_assinatura, remover_push_assinatura,
-- reservar_aviso_nova_organizacao). Executar como owner. begin/rollback.
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
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_org_nova uuid;
  v_org_velha uuid;
  v_res jsonb;
  v_n integer;
  v_endpoint text := 'https://push.exemplo.com/' || replace(gen_random_uuid()::text, '-', '');
begin
  -- A) ACL
  if has_function_privilege('anon', 'public.registrar_push_assinatura(text, text, text, text)', 'execute') then raise exception 'A: anon nao deveria registrar'; end if;
  if has_function_privilege('authenticated', 'public.reservar_aviso_nova_organizacao(uuid)', 'execute') then raise exception 'A: authenticated nao deveria reservar aviso'; end if;
  if not has_function_privilege('service_role', 'public.reservar_aviso_nova_organizacao(uuid)', 'execute') then raise exception 'A: service_role deveria reservar aviso'; end if;
  if has_table_privilege('authenticated', 'public.push_assinaturas', 'select') then raise exception 'A: authenticated nao deveria ler assinaturas'; end if;
  if has_table_privilege('anon', 'public.push_assinaturas', 'select') then raise exception 'A: anon nao deveria ler assinaturas'; end if;

  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super Push', 'superpush_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Admin Push', 'adminpush_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);

  -- B) admin comum nao registra aparelho
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.registrar_push_assinatura(v_endpoint, 'chave', 'segredo', 'teste');
    raise exception 'B: admin comum deveria ser recusado';
  exception when others then
    if position('apenas super admin' in sqlerrm) = 0 then raise exception 'B: %', sqlerrm; end if;
  end;

  -- C) super admin registra (e repetir nao duplica)
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.registrar_push_assinatura(v_endpoint, 'chave', 'segredo', 'teste');
  v_res := public.registrar_push_assinatura(v_endpoint, 'chave2', 'segredo2', 'teste');
  select count(*) into v_n from public.push_assinaturas where endpoint = v_endpoint and p256dh = 'chave2';
  if v_n <> 1 then raise exception 'C: assinatura deveria existir uma vez (%)', v_n; end if;

  -- D) endpoint invalido e recusado
  begin
    perform public.registrar_push_assinatura('http://inseguro.local/x', 'chave', 'segredo', null);
    raise exception 'D: endpoint sem https deveria ser recusado';
  exception when others then
    if position('invalida' in sqlerrm) = 0 then raise exception 'D: %', sqlerrm; end if;
  end;

  -- E) casa nova: aviso sai uma unica vez, com o aparelho do super admin
  insert into public.organizacoes (nome, slug, aprovada)
  values ('Casa Nova Push', 'casa-nova-push-' || substr(replace(gen_random_uuid()::text,'-',''),1,10), false)
  returning id into v_org_nova;
  v_res := public.reservar_aviso_nova_organizacao(v_org_nova);
  if (v_res->>'enviar')::boolean is not true then raise exception 'E: deveria enviar (%)', v_res; end if;
  if v_res->>'nome' <> 'Casa Nova Push' then raise exception 'E: nome (%)', v_res; end if;
  select count(*) into v_n from jsonb_array_elements(v_res->'assinaturas') a where a->>'endpoint' = v_endpoint;
  if v_n <> 1 then raise exception 'E: aparelho do super admin ausente (%)', v_res; end if;
  v_res := public.reservar_aviso_nova_organizacao(v_org_nova);
  if (v_res->>'enviar')::boolean is not false then raise exception 'E: segundo aviso nao deveria sair (%)', v_res; end if;

  -- F) casa antiga (mais de 1 hora) nao gera aviso
  insert into public.organizacoes (nome, slug, aprovada, criado_em)
  values ('Casa Velha Push', 'casa-velha-push-' || substr(replace(gen_random_uuid()::text,'-',''),1,10), false, now() - interval '2 hours')
  returning id into v_org_velha;
  v_res := public.reservar_aviso_nova_organizacao(v_org_velha);
  if (v_res->>'enviar')::boolean is not false then raise exception 'F: casa antiga nao deveria gerar aviso (%)', v_res; end if;

  -- G) super admin remove o aparelho
  v_res := public.remover_push_assinatura(v_endpoint);
  select count(*) into v_n from public.push_assinaturas where endpoint = v_endpoint;
  if v_n <> 0 then raise exception 'G: assinatura deveria ter sido removida (%)', v_n; end if;
end $$;

select 'push_super_admin: todos os testes passaram' as resultado;

rollback;
