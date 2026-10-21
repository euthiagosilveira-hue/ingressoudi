-- =============================================================================
-- Ingressoudi - Testes: CRM kanban, contatos e historico do lead
-- Arquivo: supabase/tests/crm_kanban_contatos.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_table_privilege('authenticated', 'public.crm_contatos', 'SELECT')
     or has_table_privilege('anon', 'public.crm_contatos', 'SELECT') then
    raise exception 'ACL: contatos do CRM nao podem ser lidos direto pelo navegador';
  end if;
  if has_function_privilege('anon', 'public.crm_registrar_contato(uuid, date, text, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.crm_mover_etapa(uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.crm_obter_produtor(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode usar o CRM';
  end if;
end $$;

do $$
declare
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_org uuid;
  v_p uuid; v_k1 uuid; v_k2 uuid;
  v_d jsonb; v_x jsonb;
begin
  delete from public.crm_produtores;

  insert into public.organizacoes (nome, slug) values ('Kanban Casa', 'kb-casa-' || substr(md5(random()::text),1,10)) returning id into v_org;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super KB', 'kb_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Admin KB', 'kb_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org where id = v_admin;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_p := (public.crm_salvar_produtor(null, '{"nome_produtor":"Produtor K","etapa":"CONTATADO","ultimo_contato":"2026-10-10"}')->>'id')::uuid;

  -- T1) admin comum nao usa as novas funcoes -----------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.crm_mover_etapa(v_p, 'INTERESSADO');
    raise exception 'T1: admin comum nao deveria mover';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;
  begin
    perform public.crm_obter_produtor(v_p);
    raise exception 'T1: admin comum nao deveria ver o historico';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1b: %', sqlerrm; end if;
  end;
  begin
    perform public.crm_registrar_contato(v_p, '2026-10-21', 'WHATSAPP', 'Oi');
    raise exception 'T1: admin comum nao deveria registrar contato';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1c: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);

  -- T2) mover de etapa grava historico; mover para a mesma etapa nao ----------------
  perform public.crm_mover_etapa(v_p, 'DEMO_AGENDADA');
  perform public.crm_mover_etapa(v_p, 'DEMO_AGENDADA');
  if (select etapa from public.crm_produtores where id = v_p) <> 'DEMO_AGENDADA' then
    raise exception 'T2: etapa nao mudou';
  end if;
  if (select count(*) from public.crm_historico where produtor_id = v_p) <> 2 then
    raise exception 'T2: historico deveria ter 2 registros';
  end if;
  begin
    perform public.crm_mover_etapa(v_p, 'FECHADO');
    raise exception 'T2: etapa invalida deveria falhar';
  exception when others then
    if position('Etapa invalida' in sqlerrm) = 0 then raise exception 'T2b: %', sqlerrm; end if;
  end;

  -- T3) contatos: validacao e ultimo contato -------------------------------------------
  begin
    perform public.crm_registrar_contato(v_p, '2026-10-21', 'FAX', 'Oi');
    raise exception 'T3: canal invalido deveria falhar';
  exception when others then
    if position('Canal invalido' in sqlerrm) = 0 then raise exception 'T3: %', sqlerrm; end if;
  end;
  begin
    perform public.crm_registrar_contato(v_p, '2026-10-21', 'WHATSAPP', '   ');
    raise exception 'T3: resumo vazio deveria falhar';
  exception when others then
    if position('conversado' in sqlerrm) = 0 then raise exception 'T3b: %', sqlerrm; end if;
  end;
  v_k1 := (public.crm_registrar_contato(v_p, '2026-10-21', 'WHATSAPP', 'Mandei o vídeo')->>'id')::uuid;
  if (select ultimo_contato from public.crm_produtores where id = v_p) <> '2026-10-21' then
    raise exception 'T3: ultimo contato deveria ir para 21/10';
  end if;
  -- contato com data antiga nao puxa o ultimo contato para tras
  v_k2 := (public.crm_registrar_contato(v_p, '2026-10-15', 'LIGACAO', 'Ligação de apresentação')->>'id')::uuid;
  if (select ultimo_contato from public.crm_produtores where id = v_p) <> '2026-10-21' then
    raise exception 'T3: contato antigo nao deveria mudar o ultimo contato';
  end if;

  -- T4) historico do lead -------------------------------------------------------------
  -- Dentro de uma transacao now() e fixo, entao os registros de etapa saem com o
  -- mesmo horario; afasta a entrada no CRM para testar a ordem (mais recente primeiro).
  update public.crm_historico set em = em - interval '1 hour'
   where produtor_id = v_p and etapa_anterior is null;
  v_d := public.crm_obter_produtor(v_p);
  if jsonb_array_length(v_d->'historico') <> 2 or v_d->'historico'->0->>'etapa_nova' <> 'DEMO_AGENDADA'
     or v_d->'historico'->0->>'etapa_anterior' <> 'CONTATADO' or v_d->'historico'->0->>'por' <> 'Super KB' then
    raise exception 'T4: historico: %', v_d->'historico';
  end if;
  if jsonb_array_length(v_d->'contatos') <> 2 or v_d->'contatos'->0->>'canal' <> 'WHATSAPP' then
    raise exception 'T4: contatos (mais recente primeiro): %', v_d->'contatos';
  end if;

  -- T5) lista traz etapa_desde e total de contatos -----------------------------------
  select x into v_x from jsonb_array_elements(public.crm_listar_produtores()) x where x->>'id' = v_p::text;
  if (v_x->>'contatos')::int <> 2 or v_x->>'etapa_desde' is null then
    raise exception 'T5: lista: %', v_x;
  end if;
  if (v_x->>'etapa_desde')::timestamptz < (select max(em) from public.crm_historico where produtor_id = v_p) then
    raise exception 'T5: etapa_desde deveria ser a entrada na etapa atual: %', v_x;
  end if;

  -- T6) excluir contato recalcula o ultimo contato -----------------------------------
  perform public.crm_excluir_contato(v_k1);
  if (select ultimo_contato from public.crm_produtores where id = v_p) <> '2026-10-15' then
    raise exception 'T6: ultimo contato deveria voltar para 15/10';
  end if;

  -- T7) excluir o produtor leva os contatos ----------------------------------------
  perform public.crm_excluir_produtor(v_p);
  if exists (select 1 from public.crm_contatos where produtor_id = v_p) then
    raise exception 'T7: contatos deveriam sair junto';
  end if;
end $$;

select 'crm_kanban_contatos: todos os testes passaram' as resultado;

rollback;
