-- =============================================================================
-- GZ1 Ingresso - Testes: Lista VIP
-- Arquivo: supabase/tests/lista_vip.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre:
--   A anon nao cria VIP
--   B PORTARIA nao cria/lista VIP
--   C ADMIN cria VIP
--   D nome obrigatorio
--   E evento inexistente
--   F evento CANCELADO/REALIZADO rejeitado
--   G nomes duplicados permitidos
--   H ADMIN edita antes da entrada
--   I protecao apos a entrada (editar/remover)
--   J busca da portaria retorna VIP
--   K busca isolada por evento
--   L PORTARIA registra entrada
--   M ADMIN registra entrada
--   N primeira entrada = LIBERADO
--   O segunda entrada = JA_UTILIZADO
--   P nao cria dupla entrada ativa
--   Q VIP nao cria pedido
--   R VIP nao cria pagamento
--   S VIP nao altera financeiro
--   T auditoria
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

-- A) anon sem EXECUTE
do $$
begin
  if has_function_privilege('anon', 'public.criar_lista_vip_admin(uuid, text, text, text)', 'EXECUTE') then
    raise exception 'A: anon nao pode criar VIP';
  end if;
  if has_function_privilege('anon', 'public.listar_lista_vip_admin(uuid, text)', 'EXECUTE') then
    raise exception 'A: anon nao pode listar VIP';
  end if;
  if has_function_privilege('anon', 'public.registrar_entrada_vip(uuid, uuid)', 'EXECUTE') then
    raise exception 'A: anon nao pode registrar entrada VIP';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();

  v_e uuid;
  v_e2 uuid;
  v_e_cancel uuid;

  v_vip1 uuid;
  v_vip2 uuid;
  v_vip3 uuid;
  v_vip_entry uuid;

  v_res jsonb;
  v_falhou boolean;
  v_msg text;
  v_n integer;
  v_pedidos_antes integer;
  v_pagamentos_antes integer;
  v_pedidos_depois integer;
  v_pagamentos_depois integer;
  v_fin jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Fixtures
  -- -------------------------------------------------------------------------
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin VIP', 'adminvip_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port VIP', 'portvip_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento VIP','vip-'||replace(gen_random_uuid()::text,'-',''), now()-interval '1 hour','L','E',100,50,'EM_ANDAMENTO','PUBLICADO','ENCERRADAS')
  returning id into v_e;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento VIP 2','vip2-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,50,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e2;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento VIP Cancel','vipc-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,50,'CANCELADO','PUBLICADO','ENCERRADAS')
  returning id into v_e_cancel;

  select count(*) into v_pedidos_antes from public.pedidos;
  select count(*) into v_pagamentos_antes from public.pagamentos;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- -------------------------------------------------------------------------
  -- B) PORTARIA nao cria/lista VIP
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_falhou := false;
  begin
    perform public.criar_lista_vip_admin(v_e, 'Portaria Indevida');
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'B: PORTARIA nao deveria criar VIP'; end if;

  v_falhou := false;
  begin
    perform public.listar_lista_vip_admin(v_e);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'B: PORTARIA nao deveria listar VIP'; end if;

  -- -------------------------------------------------------------------------
  -- C) ADMIN cria VIP
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_res := public.criar_lista_vip_admin(v_e, 'Thiago Convidado', '11999990000', 'Camarote');
  v_vip1 := (v_res->>'vip_id')::uuid;
  if v_vip1 is null then raise exception 'C: vip_id deveria ser retornado'; end if;

  -- -------------------------------------------------------------------------
  -- D) nome obrigatorio
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_lista_vip_admin(v_e, '   ');
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'D: nome vazio deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- E) evento inexistente
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_lista_vip_admin(gen_random_uuid(), 'Sem Evento');
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'E: evento inexistente deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- F) evento CANCELADO rejeitado
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_lista_vip_admin(v_e_cancel, 'Cancelado');
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'F: evento CANCELADO deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- G) nomes duplicados permitidos
  -- -------------------------------------------------------------------------
  v_res := public.criar_lista_vip_admin(v_e, 'Thiago Convidado');
  v_vip2 := (v_res->>'vip_id')::uuid;
  v_res := public.criar_lista_vip_admin(v_e, 'Thiago Convidado');
  v_vip3 := (v_res->>'vip_id')::uuid;
  if v_vip2 = v_vip3 or v_vip1 = v_vip2 then
    raise exception 'G: nomes duplicados deveriam gerar registros distintos';
  end if;

  -- -------------------------------------------------------------------------
  -- H) ADMIN edita antes da entrada
  -- -------------------------------------------------------------------------
  perform public.atualizar_lista_vip_admin(v_vip2, 'Thiago Editado', '11888887777', 'Obs nova');
  if not exists (
    select 1 from public.lista_vip lv
     where lv.id = v_vip2 and lv.nome = 'Thiago Editado' and lv.telefone = '11888887777'
  ) then
    raise exception 'H: edicao antes da entrada deveria aplicar';
  end if;

  -- -------------------------------------------------------------------------
  -- J/K) Busca da portaria retorna VIP e respeita o evento
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);

  v_res := public.buscar_ingressos_por_nome(v_e, 'Thiago Editado');
  if not exists (
    select 1 from jsonb_array_elements(v_res) el
     where el->>'origem' = 'VIP' and el->>'vip_id' = v_vip2::text and el->>'status' = 'VALIDO'
  ) then
    raise exception 'J: busca deveria retornar o convidado VIP';
  end if;

  v_res := public.buscar_ingressos_por_nome(v_e2, 'Thiago Editado');
  if jsonb_array_length(v_res) <> 0 then
    raise exception 'K: busca em outro evento nao deveria retornar VIP de outro evento';
  end if;

  -- -------------------------------------------------------------------------
  -- L/N) PORTARIA registra entrada -> LIBERADO
  -- -------------------------------------------------------------------------
  v_res := public.registrar_entrada_vip(v_e, v_vip1);
  if (v_res->>'resultado') <> 'LIBERADO' then
    raise exception 'L/N: primeira entrada deveria ser LIBERADO (obtido %)', v_res->>'resultado';
  end if;
  if (v_res->>'vip_id') <> v_vip1::text then raise exception 'L: vip_id incorreto'; end if;

  -- apos entrada, busca mostra UTILIZADO
  v_res := public.buscar_ingressos_por_nome(v_e, 'Thiago Convidado');
  if not exists (
    select 1 from jsonb_array_elements(v_res) el
     where el->>'vip_id' = v_vip1::text and el->>'status' = 'UTILIZADO' and (el->>'entrada_em') is not null
  ) then
    raise exception 'N: busca deveria mostrar VIP UTILIZADO com horario';
  end if;

  -- -------------------------------------------------------------------------
  -- O/P) segunda entrada = JA_UTILIZADO e sem dupla entrada ativa
  -- -------------------------------------------------------------------------
  v_res := public.registrar_entrada_vip(v_e, v_vip1);
  if (v_res->>'resultado') <> 'JA_UTILIZADO' then
    raise exception 'O: segunda entrada deveria ser JA_UTILIZADO (obtido %)', v_res->>'resultado';
  end if;

  select count(*) into v_n from public.entradas_vip ev
   where ev.lista_vip_id = v_vip1 and ev.anulada_em is null;
  if v_n <> 1 then raise exception 'P: deveria haver exatamente 1 entrada ativa (obtido %)', v_n; end if;

  -- -------------------------------------------------------------------------
  -- I) protecao apos a entrada
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_falhou := false;
  begin
    perform public.atualizar_lista_vip_admin(v_vip1, 'Nome Apos Entrada');
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'I: editar apos entrada deveria falhar'; end if;

  v_falhou := false;
  begin
    perform public.remover_lista_vip_admin(v_vip1);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'I: remover apos entrada deveria falhar'; end if;

  -- remocao antes da entrada funciona
  perform public.remover_lista_vip_admin(v_vip3);
  if not exists (
    select 1 from public.lista_vip lv where lv.id = v_vip3 and lv.ativo = false
  ) then
    raise exception 'I: remocao logica antes da entrada deveria marcar ativo=false';
  end if;

  -- -------------------------------------------------------------------------
  -- M) ADMIN registra entrada de outro VIP
  -- -------------------------------------------------------------------------
  v_res := public.criar_lista_vip_admin(v_e, 'Convidado Admin');
  v_vip_entry := (v_res->>'vip_id')::uuid;
  v_res := public.registrar_entrada_vip(v_e, v_vip_entry);
  if (v_res->>'resultado') <> 'LIBERADO' then
    raise exception 'M: ADMIN deveria registrar entrada (obtido %)', v_res->>'resultado';
  end if;

  -- -------------------------------------------------------------------------
  -- Q/R/S) VIP nao cria pedido/pagamento nem altera financeiro
  -- -------------------------------------------------------------------------
  select count(*) into v_pedidos_depois from public.pedidos;
  select count(*) into v_pagamentos_depois from public.pagamentos;
  if v_pedidos_depois <> v_pedidos_antes then
    raise exception 'Q: VIP nao deveria criar pedido (antes=%, depois=%)', v_pedidos_antes, v_pedidos_depois;
  end if;
  if v_pagamentos_depois <> v_pagamentos_antes then
    raise exception 'R: VIP nao deveria criar pagamento (antes=%, depois=%)', v_pagamentos_antes, v_pagamentos_depois;
  end if;

  v_fin := public.obter_financeiro_admin(p_evento_id => v_e);
  if jsonb_array_length(v_fin->'movimentacoes') <> 0 then
    raise exception 'S: financeiro do evento nao deveria ter movimentacoes VIP';
  end if;

  -- -------------------------------------------------------------------------
  -- T) auditoria
  -- -------------------------------------------------------------------------
  select count(*) into v_n from public.auditoria a
   where a.acao = 'VIP_ADICIONADO' and a.entidade = 'lista_vip';
  if v_n < 1 then raise exception 'T: auditoria VIP_ADICIONADO ausente'; end if;

  select count(*) into v_n from public.auditoria a
   where a.acao = 'VIP_ATUALIZADO' and a.entidade_id = v_vip2;
  if v_n <> 1 then raise exception 'T: auditoria VIP_ATUALIZADO ausente'; end if;

  select count(*) into v_n from public.auditoria a
   where a.acao = 'VIP_REMOVIDO' and a.entidade_id = v_vip3;
  if v_n <> 1 then raise exception 'T: auditoria VIP_REMOVIDO ausente'; end if;

  select count(*) into v_n from public.auditoria a
   where a.acao = 'VIP_ENTRADA_REGISTRADA' and a.entidade = 'entradas_vip';
  if v_n <> 2 then raise exception 'T: auditoria VIP_ENTRADA_REGISTRADA deveria ter 2 registros'; end if;
end $$;

select 'lista_vip: todos os testes passaram' as resultado;

rollback;
