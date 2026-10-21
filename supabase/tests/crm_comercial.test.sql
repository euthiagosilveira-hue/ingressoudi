-- =============================================================================
-- Ingressoudi - Testes: CRM comercial (Plataforma, somente super admin)
-- Arquivo: supabase/tests/crm_comercial.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

do $$
begin
  if has_table_privilege('authenticated', 'public.crm_produtores', 'SELECT')
     or has_table_privilege('anon', 'public.crm_produtores', 'SELECT')
     or has_table_privilege('authenticated', 'public.crm_historico', 'SELECT') then
    raise exception 'ACL: o CRM nao pode ser lido direto pelo navegador';
  end if;
  if has_function_privilege('anon', 'public.crm_listar_produtores()', 'EXECUTE')
     or has_function_privilege('anon', 'public.crm_salvar_produtor(uuid, jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.crm_indicadores(date, date)', 'EXECUTE') then
    raise exception 'ACL: anon nao pode usar o CRM';
  end if;
end $$;

do $$
declare
  v_super uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_org uuid; v_org_nova uuid;
  v_ev uuid;
  v_a uuid; v_b uuid;
  v_res jsonb; v_pag jsonb; v_l jsonb; v_i jsonb; v_x jsonb;
begin
  -- Comeca com o CRM vazio (o rollback devolve o que ja existia)
  delete from public.crm_produtores;

  insert into public.organizacoes (nome, slug, taxa_servico) values ('CRM Casa', 'crm-casa-' || substr(md5(random()::text),1,10), 2.00) returning id into v_org;
  insert into public.organizacoes (nome, slug) values ('CRM Nova', 'crm-nova-' || substr(md5(random()::text),1,10)) returning id into v_org_nova;
  insert into auth.users (id) values (v_super), (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin) values
    (v_super, 'Super', 'crm_s_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true),
    (v_admin, 'Dono Nova', 'crm_a_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values (v_org_nova, v_admin, 'ADMINISTRADOR');
  update public.usuarios set organizacao_ativa_id = v_org_nova where id = v_admin;

  -- Casa com um evento publicado e uma venda online (2 x 10 + taxa 2 x 2,00)
  insert into public.eventos (organizacao_id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, publicado_em, vendas_status, taxa_repassada)
  values (v_org, 'Show CRM', 'crm-ev-' || substr(md5(random()::text),1,8), now() + interval '5 days', 'Casa', 'Rua', 100, 80, 'AGENDADO', 'PUBLICADO', now(), 'ABERTAS', true)
  returning id into v_ev;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_ev, 'Primeiro lote', 1, 50, 10.00, 'MANUAL', 'ATIVO');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_res := public.criar_reserva(v_ev, 'C1', '11999990000', null, array['Ana', 'Bia']);
  v_pag := public.criar_pagamento_pendente_por_token((v_res->>'checkout_token')::uuid, 'MERCADO_PAGO');
  perform public.confirmar_pagamento((v_pag->>'pagamento_id')::uuid, 'crm-1', null);

  -- T1) administrador de casa nao acessa o CRM -----------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  begin
    perform public.crm_listar_produtores();
    raise exception 'T1: admin comum nao deveria listar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;
  begin
    perform public.crm_salvar_produtor(null, '{"nome_produtor":"X"}');
    raise exception 'T1: admin comum nao deveria salvar';
  exception when others then
    if position('super administrador' in lower(sqlerrm)) = 0 then raise exception 'T1b: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);

  -- T2) validacoes ---------------------------------------------------------------------
  begin
    perform public.crm_salvar_produtor(null, '{"nome_produtor":"  "}');
    raise exception 'T2: nome vazio deveria falhar';
  exception when others then
    if position('nome do produtor' in sqlerrm) = 0 then raise exception 'T2: %', sqlerrm; end if;
  end;
  begin
    perform public.crm_salvar_produtor(null, '{"nome_produtor":"A","etapa":"FECHADO"}');
    raise exception 'T2: etapa invalida deveria falhar';
  exception when others then
    if position('Etapa invalida' in sqlerrm) = 0 then raise exception 'T2b: %', sqlerrm; end if;
  end;

  -- T3) cria, edita e registra a mudanca de etapa ----------------------------------------
  v_a := (public.crm_salvar_produtor(null, jsonb_build_object(
    'nome_produtor', 'Produtor A', 'empresa_evento', 'Festa X', 'cidade', 'Uberlândia',
    'tipo_evento', 'Festa universitária', 'etapa', 'CONTATADO', 'whatsapp', '',
    'proxima_acao', 'Agendar demonstração', 'proxima_acao_em', '2026-10-23',
    'ultimo_contato', '2026-10-21'))->>'id')::uuid;
  if (select whatsapp from public.crm_produtores where id = v_a) is not null then
    raise exception 'T3: texto vazio deveria virar null';
  end if;
  perform public.crm_salvar_produtor(v_a, jsonb_build_object(
    'nome_produtor', 'Produtor A', 'empresa_evento', 'Festa X', 'etapa', 'DEMO_REALIZADA',
    'organizacao_id', v_org::text));
  if (select count(*) from public.crm_historico where produtor_id = v_a) <> 2 then
    raise exception 'T3: historico deveria ter 2 registros';
  end if;
  -- salvar sem mudar a etapa nao gera historico
  perform public.crm_salvar_produtor(v_a, jsonb_build_object(
    'nome_produtor', 'Produtor A', 'etapa', 'DEMO_REALIZADA', 'organizacao_id', v_org::text));
  if (select count(*) from public.crm_historico where produtor_id = v_a) <> 2 then
    raise exception 'T3: salvar sem mudar a etapa nao deveria gerar historico';
  end if;

  -- T4) uma casa so pode estar ligada a um produtor -----------------------------------
  v_b := (public.crm_salvar_produtor(null, '{"nome_produtor":"Produtor B"}')->>'id')::uuid;
  begin
    perform public.crm_salvar_produtor(v_b, jsonb_build_object('nome_produtor', 'Produtor B', 'organizacao_id', v_org::text));
    raise exception 'T4: casa duplicada deveria falhar';
  exception when others then
    if position('ja esta ligada' in sqlerrm) = 0 then raise exception 'T4: %', sqlerrm; end if;
  end;

  -- T5) lista traz os numeros reais da casa ligada ----------------------------------
  v_l := public.crm_listar_produtores();
  select x into v_x from jsonb_array_elements(v_l) x where x->>'id' = v_a::text;
  if (v_x->>'eventos_publicados')::int <> 1 or (v_x->>'ingressos_vendidos')::int <> 2
     or (v_x->>'receita_gerada')::numeric <> 24 or v_x->>'organizacao_nome' <> 'CRM Casa' then
    raise exception 'T5: produtor A: %', v_x;
  end if;
  select x into v_x from jsonb_array_elements(v_l) x where x->>'id' = v_b::text;
  if (v_x->>'eventos_publicados')::int <> 0 or (v_x->>'receita_gerada')::numeric <> 0 then
    raise exception 'T5: produtor B: %', v_x;
  end if;

  -- T6) indicadores: pular etapas conta as anteriores ---------------------------------
  v_i := public.crm_indicadores(null, null);
  if (v_i->'funil'->0->>'alcancaram')::int <> 2           -- mapeado: A e B
     or (v_i->'funil'->1->>'alcancaram')::int <> 1        -- contatado: A
     or (v_i->'funil'->2->>'alcancaram')::int <> 1        -- interessado: A (pulou)
     or (v_i->'funil'->4->>'alcancaram')::int <> 1        -- demo realizada: A
     or (v_i->'funil'->5->>'alcancaram')::int <> 0
     or (v_i->'funil'->0->>'atual')::int <> 1             -- B esta em Mapeado
     or (v_i->'funil'->4->>'atual')::int <> 1 then
    raise exception 'T6: funil: %', v_i->'funil';
  end if;
  if (v_i->'negocio'->>'eventos_publicados')::int <> 1
     or (v_i->'negocio'->>'ingressos_vendidos')::int <> 2
     or (v_i->'negocio'->>'receita_liquida')::numeric <> 4 then
    raise exception 'T6: negocio: %', v_i->'negocio';
  end if;
  if (v_i->'acoes'->>'total_produtores')::int <> 2 then raise exception 'T6: acoes: %', v_i->'acoes'; end if;

  -- periodo no passado nao traz nada
  v_i := public.crm_indicadores('2020-01-01', '2020-01-31');
  if (v_i->'funil'->0->>'alcancaram')::int <> 0 or (v_i->'negocio'->>'ingressos_vendidos')::int <> 0 then
    raise exception 'T6: periodo antigo: %', v_i;
  end if;
  begin
    perform public.crm_indicadores('2026-10-10', '2026-10-01');
    raise exception 'T6: periodo invertido deveria falhar';
  exception when others then
    if position('Periodo invalido' in sqlerrm) = 0 then raise exception 'T6c: %', sqlerrm; end if;
  end;

  -- T7) importar casas: so as que ainda nao estao no CRM ------------------------------
  v_x := public.crm_importar_casas();
  if not exists (select 1 from public.crm_produtores c
                  where c.organizacao_id = v_org_nova and c.nome_produtor = 'Dono Nova'
                    and c.empresa_evento = 'CRM Nova' and c.etapa = 'CADASTRO_INICIADO') then
    raise exception 'T7: casa nova deveria entrar como Cadastro iniciado';
  end if;
  if (select count(*) from public.crm_produtores c where c.organizacao_id = v_org) <> 1 then
    raise exception 'T7: casa ja ligada nao pode duplicar';
  end if;
  if (public.crm_importar_casas()->>'importados')::int <> 0 then
    raise exception 'T7: segunda importacao deveria ser vazia';
  end if;

  -- T8) excluir -----------------------------------------------------------------------
  perform public.crm_excluir_produtor(v_b);
  if exists (select 1 from public.crm_historico where produtor_id = v_b) then
    raise exception 'T8: historico deveria sair junto';
  end if;
end $$;

select 'crm_comercial: todos os testes passaram' as resultado;

rollback;
