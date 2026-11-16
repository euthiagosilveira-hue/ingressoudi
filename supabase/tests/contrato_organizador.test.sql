-- =============================================================================
-- Ingressoudi - Testes: CPF/CNPJ do organizador + Contrato do Organizador
-- Arquivo: supabase/tests/contrato_organizador.test.sql
-- Executar como owner. begin/rollback (nao persiste dados).
-- =============================================================================

begin;

-- ACL ---------------------------------------------------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.registrar_aceite_contrato(uuid,uuid,text,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.registrar_aceite_contrato(uuid,uuid,text,text,text)', 'EXECUTE') then
    raise exception 'ACL: aceite so pode ser gravado pelo servidor (service role)';
  end if;
  if not has_function_privilege('service_role', 'public.registrar_aceite_contrato(uuid,uuid,text,text,text)', 'EXECUTE') then
    raise exception 'ACL: service role precisa gravar o aceite';
  end if;
  if has_table_privilege('authenticated', 'public.aceites_contrato_organizador', 'SELECT')
     or has_table_privilege('anon', 'public.aceites_contrato_organizador', 'SELECT')
     or has_table_privilege('authenticated', 'public.aceites_contrato_organizador', 'INSERT') then
    raise exception 'ACL: tabela de aceites nao pode ser lida/gravada direto pelo app';
  end if;
  if has_function_privilege('anon', 'public.salvar_dados_organizador(text,text,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.obter_contrato_organizacao_plataforma(uuid)', 'EXECUTE') then
    raise exception 'ACL: anon nao acessa dados do organizador';
  end if;
end $$;

-- VALIDADORES ---------------------------------------------------------------------
do $$
begin
  if not private.cpf_valido('529.982.247-25') then raise exception 'CPF valido recusado'; end if;
  if private.cpf_valido('529.982.247-24') then raise exception 'CPF com DV errado aceito'; end if;
  if private.cpf_valido('111.111.111-11') then raise exception 'CPF repetido aceito'; end if;
  if private.cpf_valido('1234') then raise exception 'CPF curto aceito'; end if;
  if not private.cnpj_valido('11.222.333/0001-81') then raise exception 'CNPJ valido recusado'; end if;
  if private.cnpj_valido('11.222.333/0001-80') then raise exception 'CNPJ com DV errado aceito'; end if;
  if private.cnpj_valido('00000000000000') then raise exception 'CNPJ repetido aceito'; end if;
  if private.documento_exibicao('CPF', '52998224725') <> '***.982.247-**' then raise exception 'mascara CPF'; end if;
  if private.documento_exibicao('CNPJ', '11222333000181') <> '11.222.333/0001-81' then raise exception 'formato CNPJ'; end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_port uuid := gen_random_uuid();
  v_super uuid := gen_random_uuid();
  v_novo uuid := gen_random_uuid();
  v_org uuid;
  v_slug text := 'ctr-' || substr(replace(gen_random_uuid()::text,'-',''), 1, 10);
  v_res jsonb; v_ev uuid; v_n int;
begin
  insert into auth.users (id, email) values
    (v_admin, 'adm_' || replace(v_admin::text,'-','') || '@test.local'),
    (v_port, 'port_' || replace(v_port::text,'-','') || '@test.local'),
    (v_super, 'sup_' || replace(v_super::text,'-','') || '@test.local'),
    (v_novo, 'novo_' || replace(v_novo::text,'-','') || '@test.local');
  insert into public.organizacoes (nome, slug, contrato_exigido) values ('Casa Ctr', v_slug, true) returning id into v_org;
  insert into public.usuarios (id, nome, email, perfil, ativo, super_admin, organizacao_ativa_id) values
    (v_admin, 'Admin', 'adm_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true, false, v_org),
    (v_port, 'Port', 'port_' || replace(v_port::text,'-','') || '@test.local', 'PORTARIA', true, false, v_org),
    (v_super, 'Super', 'sup_' || replace(v_super::text,'-','') || '@test.local', 'ADMINISTRADOR', true, true, null);
  insert into public.membros_organizacao (organizacao_id, usuario_id, perfil) values
    (v_org, v_admin, 'ADMINISTRADOR'), (v_org, v_port, 'PORTARIA');

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- T1) casa exigida sem dados: sessao indica pendencia e nao publica ------------
  if (public.obter_sessao_operador()->'organizacao'->>'contrato_pendente')::boolean is not true then
    raise exception 'T1: sessao deveria indicar contrato pendente';
  end if;
  v_res := public.criar_evento_admin('Show C', 'show-c', null, null,
                                     now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'RASCUNHO', 'ENCERRADAS');
  v_ev := (v_res->>'evento_id')::uuid;
  begin
    perform public.atualizar_evento_admin(v_ev, 'Show C', 'show-c', null, null,
                                          now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', null);
    raise exception 'T1: sem contrato nao deveria publicar';
  exception when others then
    if position('contrato do organizador' in lower(sqlerrm)) = 0 then raise exception 'T1: %', sqlerrm; end if;
  end;

  -- T2) validacao ao salvar os dados ---------------------------------------------
  begin
    perform public.salvar_dados_organizador('CPF', '529.982.247-24', 'Fulano', '34999990000');
    raise exception 'T2: CPF invalido aceito';
  exception when others then
    if position('cpf invalido' in lower(sqlerrm)) = 0 then raise exception 'T2 cpf: %', sqlerrm; end if;
  end;
  begin
    perform public.salvar_dados_organizador('CPF', '529.982.247-25', 'Fulano', '9999');
    raise exception 'T2: telefone invalido aceito';
  exception when others then
    if position('telefone' in lower(sqlerrm)) = 0 then raise exception 'T2 tel: %', sqlerrm; end if;
  end;
  begin
    perform public.salvar_dados_organizador('CPF', '529.982.247-25', '  ', '34999990000');
    raise exception 'T2: nome vazio aceito';
  exception when others then
    if position('nome' in lower(sqlerrm)) = 0 then raise exception 'T2 nome: %', sqlerrm; end if;
  end;

  -- T3) aceite antes dos dados completos e recusado ------------------------------
  begin
    perform private.registrar_aceite_contrato(v_admin, v_org, private.contrato_organizador_versao(), '1.2.3.4', 'ua');
    raise exception 'T3: aceite sem dados deveria falhar';
  exception when others then
    if position('complete os dados' in lower(sqlerrm)) = 0 then raise exception 'T3: %', sqlerrm; end if;
  end;

  v_res := public.salvar_dados_organizador('cpf', '529.982.247-25', ' Fulano de Tal ', '(34) 99999-0000');
  if v_res->>'documento' <> '52998224725' or v_res->>'telefone' <> '34999990000'
     or v_res->>'tipo_documento' <> 'CPF' or v_res->>'responsavel_nome' <> 'Fulano de Tal' then
    raise exception 'T3: dados nao normalizados: %', v_res;
  end if;
  if (v_res->>'contrato_pendente')::boolean is not true then raise exception 'T3: ainda falta o aceite'; end if;

  -- T4) portaria nao aceita; versao antiga recusada --------------------------------
  begin
    perform private.registrar_aceite_contrato(v_port, v_org, private.contrato_organizador_versao(), '1.2.3.4', 'ua');
    raise exception 'T4: portaria nao deveria aceitar';
  exception when others then
    if position('administrador' in lower(sqlerrm)) = 0 then raise exception 'T4: %', sqlerrm; end if;
  end;
  begin
    perform private.registrar_aceite_contrato(v_admin, v_org, 'v0', '1.2.3.4', 'ua');
    raise exception 'T4: versao antiga deveria falhar';
  exception when others then
    if position('desatualizada' in lower(sqlerrm)) = 0 then raise exception 'T4 versao: %', sqlerrm; end if;
  end;

  -- T5) aceite valido libera e grava a prova --------------------------------------
  v_res := public.registrar_aceite_contrato(v_admin, v_org, private.contrato_organizador_versao(), '200.1.2.3', 'Mozilla/5.0');
  select count(*) into v_n from public.aceites_contrato_organizador
   where organizacao_id = v_org and usuario_id = v_admin and ip = '200.1.2.3' and user_agent = 'Mozilla/5.0'
     and documento = '52998224725' and versao = private.contrato_organizador_versao();
  if v_n <> 1 then raise exception 'T5: aceite nao gravado corretamente'; end if;
  if (public.obter_sessao_operador()->'organizacao'->>'contrato_pendente')::boolean is not false then
    raise exception 'T5: sessao deveria liberar apos aceite';
  end if;
  perform public.atualizar_evento_admin(v_ev, 'Show C', 'show-c', null, null,
                                        now() + interval '3 days', 'Casa', 'Rua', 100, 50, 'PUBLICADO', null);
  if (public.obter_dados_organizador()->'ultimo_aceite'->>'usuario_nome') <> 'Admin' then
    raise exception 'T5: ultimo aceite deveria aparecer na tela';
  end if;

  -- T6) registro de aceite e imutavel ---------------------------------------------
  begin
    update public.aceites_contrato_organizador set ip = 'x' where organizacao_id = v_org;
    raise exception 'T6: update deveria falhar';
  exception when others then
    if position('nao pode ser alterado' in lower(sqlerrm)) = 0 then raise exception 'T6: %', sqlerrm; end if;
  end;
  begin
    delete from public.aceites_contrato_organizador where organizacao_id = v_org;
    raise exception 'T6: delete deveria falhar';
  exception when others then
    if position('nao pode ser alterado' in lower(sqlerrm)) = 0 then raise exception 'T6 delete: %', sqlerrm; end if;
  end;

  -- T7) pagina publica mostra organizador com CPF mascarado -----------------------
  if public.obter_organizacao_publica(v_slug)->>'organizador_documento' <> '***.982.247-**'
     or public.obter_organizacao_publica(v_slug)->>'organizador_nome' <> 'Fulano de Tal' then
    raise exception 'T7: organizador publico incorreto: %', public.obter_organizacao_publica(v_slug);
  end if;

  -- T8) super admin ve dados e aceites; admin nao ---------------------------------
  begin
    perform public.obter_contrato_organizacao_plataforma(v_org);
    raise exception 'T8: admin da casa nao usa a rota da plataforma';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'T8: %', sqlerrm; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_super::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_super::text, true);
  v_res := public.obter_contrato_organizacao_plataforma(v_org);
  if jsonb_array_length(v_res->'aceites') <> 1 or v_res->'aceites'->0->>'ip' <> '200.1.2.3'
     or (v_res->>'contrato_pendente')::boolean then
    raise exception 'T8: detalhe da plataforma incorreto: %', v_res;
  end if;

  -- T9) cadastro novo grava documento e telefone, e exige contrato ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_novo::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_novo::text, true);
  begin
    perform public.concluir_cadastro_produtor('Novo', 'Casa X', 'x-' || v_slug, 'v1', 'CNPJ', '11222333000180', 'X Ltda', '34999990000');
    raise exception 'T9: CNPJ invalido no cadastro deveria falhar';
  exception when others then
    if position('cnpj invalido' in lower(sqlerrm)) = 0 then raise exception 'T9: %', sqlerrm; end if;
  end;
  v_res := public.concluir_cadastro_produtor('Novo', 'Casa X', 'x-' || v_slug, 'v1',
                                             'CNPJ', '11.222.333/0001-81', 'X Eventos Ltda', '(34) 3333-4444');
  if not exists (select 1 from public.organizacoes where id = (v_res->>'organizacao_id')::uuid
                    and contrato_exigido and tipo_documento = 'CNPJ' and documento = '11222333000181'
                    and responsavel_nome = 'X Eventos Ltda' and telefone = '3433334444') then
    raise exception 'T9: dados do cadastro nao gravados';
  end if;
  if (public.obter_sessao_operador()->'organizacao'->>'contrato_pendente')::boolean is not true then
    raise exception 'T9: casa nova sem aceite deveria estar pendente';
  end if;
end $$;

rollback;
