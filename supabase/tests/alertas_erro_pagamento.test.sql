-- =============================================================================
-- Ingressoudi - Testes: alertas de erro em pagamentos
-- (registrar_erro_pagamento, listar_erros_pagamento_plataforma).
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
  v_org uuid := current_setting('teste.organizacao_id')::uuid;
  v_res jsonb;
  v_n integer;
  v_endpoint text := 'https://push.exemplo.com/' || replace(gen_random_uuid()::text, '-', '');
begin
  -- A) ACL
  if has_function_privilege('anon', 'public.registrar_erro_pagamento(text, uuid, text, jsonb, text)', 'execute') then raise exception 'A: anon nao deveria registrar'; end if;
  if has_function_privilege('authenticated', 'public.registrar_erro_pagamento(text, uuid, text, jsonb, text)', 'execute') then raise exception 'A: authenticated nao deveria registrar'; end if;
  if not has_function_privilege('service_role', 'public.registrar_erro_pagamento(text, uuid, text, jsonb, text)', 'execute') then raise exception 'A: service_role deveria registrar'; end if;
  if has_function_privilege('anon', 'public.listar_erros_pagamento_plataforma(integer)', 'execute') then raise exception 'A: anon nao deveria listar'; end if;
  if has_table_privilege('authenticated', 'public.erros_pagamento', 'select') then raise exception 'A: authenticated nao deveria ler a tabela'; end if;

  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super Erro', 'supererro_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Admin Erro', 'adminerro_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.push_assinaturas (usuario_id, endpoint, p256dh, auth) values (v_super, v_endpoint, 'chave', 'segredo');

  -- B) primeiro erro avisa, com o aparelho do super admin e o nome da casa
  v_res := public.registrar_erro_pagamento('PIX_CRIACAO', v_org, 'Falha ao gerar Pix', '{"httpStatus":500}'::jsonb, 'pag-1');
  if (v_res->>'enviar')::boolean is not true then raise exception 'B: deveria avisar (%)', v_res; end if;
  if v_res->>'organizacao_nome' <> 'Org Teste' then raise exception 'B: nome da casa (%)', v_res; end if;
  select count(*) into v_n from jsonb_array_elements(v_res->'assinaturas') a where a->>'endpoint' = v_endpoint;
  if v_n <> 1 then raise exception 'B: aparelho do super admin ausente (%)', v_res; end if;

  -- C) mesmo tipo e casa em seguida: grava, mas nao avisa
  v_res := public.registrar_erro_pagamento('PIX_CRIACAO', v_org, 'Falha ao gerar Pix de novo', null, 'pag-2');
  if (v_res->>'enviar')::boolean is not false then raise exception 'C: nao deveria avisar de novo (%)', v_res; end if;
  if jsonb_array_length(v_res->'assinaturas') <> 0 then raise exception 'C: nao deveria devolver aparelhos (%)', v_res; end if;
  select count(*) into v_n from public.erros_pagamento where organizacao_id = v_org and tipo = 'PIX_CRIACAO';
  if v_n <> 2 then raise exception 'C: os dois erros deveriam estar gravados (%)', v_n; end if;

  -- D) outro tipo avisa; erro sem casa (ou casa inexistente) tambem
  v_res := public.registrar_erro_pagamento('REEMBOLSO', v_org, 'Reembolso recusado', null, null);
  if (v_res->>'enviar')::boolean is not true then raise exception 'D: outro tipo deveria avisar (%)', v_res; end if;
  v_res := public.registrar_erro_pagamento('WEBHOOK', gen_random_uuid(), 'Assinatura invalida', null, null);
  if (v_res->>'enviar')::boolean is not true then raise exception 'D: erro sem casa deveria avisar (%)', v_res; end if;
  select count(*) into v_n from public.erros_pagamento where tipo = 'WEBHOOK' and organizacao_id is null;
  if v_n <> 1 then raise exception 'D: casa inexistente deveria virar null (%)', v_n; end if;

  -- E) depois de 15 minutos volta a avisar
  update public.erros_pagamento set criado_em = now() - interval '16 minutes' where organizacao_id = v_org and tipo = 'PIX_CRIACAO';
  v_res := public.registrar_erro_pagamento('PIX_CRIACAO', v_org, 'Falha ao gerar Pix', null, null);
  if (v_res->>'enviar')::boolean is not true then raise exception 'E: deveria avisar apos 15 minutos (%)', v_res; end if;

  -- F) tipo invalido e recusado
  begin
    perform public.registrar_erro_pagamento('INVENTADO', v_org, 'x', null, null);
    raise exception 'F: tipo invalido deveria ser recusado';
  exception when check_violation then null;
  end;

  -- G) admin comum nao lista; super admin lista com o nome da casa
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.listar_erros_pagamento_plataforma(50);
    raise exception 'G: admin comum deveria ser recusado';
  exception when others then
    if position('apenas super administrador' in sqlerrm) = 0 then raise exception 'G: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.listar_erros_pagamento_plataforma(50);
  select count(*) into v_n from jsonb_array_elements(v_res) l where l->>'organizacao_nome' = 'Org Teste' and l->>'tipo' = 'REEMBOLSO';
  if v_n <> 1 then raise exception 'G: lista deveria trazer o reembolso da casa (%)', v_res; end if;
  if (v_res->0->>'criado_em')::timestamptz < (v_res->-1->>'criado_em')::timestamptz then raise exception 'G: lista deveria vir do mais novo para o mais antigo'; end if;
end $$;

select 'alertas_erro_pagamento: todos os testes passaram' as resultado;

rollback;
