-- =============================================================================
-- GZ1 Ingresso - Testes: Lista VIP cadastro em lote
-- Arquivo: supabase/tests/lista_vip_lote.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre:
--   A anon negado
--   B PORTARIA negado
--   C ADMIN cria varios
--   D lista vazia rejeitada
--   E mais de 100 rejeitado
--   F nome vazio rejeitado
--   G nomes duplicados permitidos
--   H evento inexistente rejeitado
--   I evento invalido (CANCELADO) rejeitado
--   J todos recebem evento_id correto
--   K todos recebem criado_por correto
--   L telefone null
--   M observacao null
--   N operacao atomica (nome invalido nao cria nenhum)
--   O auditoria VIP_LOTE_ADICIONADO
--   P busca da portaria encontra os convidados
-- =============================================================================

begin;

-- A) anon sem EXECUTE
do $$
begin
  if has_function_privilege('anon', 'public.criar_lista_vip_em_lote_admin(uuid, text[])', 'EXECUTE') then
    raise exception 'A: anon nao pode executar criar_lista_vip_em_lote_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();

  v_e uuid;
  v_e_cancel uuid;

  v_res jsonb;
  v_falhou boolean;
  v_qtd integer;
  v_n integer;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Lote', 'adminlote_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Lote', 'portlote_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Lote VIP','lotevip-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,50,'AGENDADO','RASCUNHO','ENCERRADAS')
  returning id into v_e;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Lote Cancel','lotevipc-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,50,'CANCELADO','RASCUNHO','ENCERRADAS')
  returning id into v_e_cancel;

  -- B) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e, array['Portaria Indevida']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'B: PORTARIA nao deveria criar em lote'; end if;

  -- C) ADMIN cria varios
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_res := public.criar_lista_vip_em_lote_admin(v_e, array['João Silva', 'Maria Souza', 'Carlos Ferreira']);
  if (v_res->>'quantidade_criada')::int <> 3 then
    raise exception 'C: quantidade_criada deveria ser 3 (obtido %)', v_res->>'quantidade_criada';
  end if;

  -- J/K/L/M) todos com evento_id, criado_por, telefone null, observacao null
  select count(*) into v_n from public.lista_vip lv
   where lv.evento_id = v_e
     and lv.criado_por_usuario_id = v_admin
     and lv.telefone is null
     and lv.observacao is null;
  if v_n <> 3 then raise exception 'J/K/L/M: esperado 3 registros coerentes (obtido %)', v_n; end if;

  -- G) duplicados permitidos
  v_res := public.criar_lista_vip_em_lote_admin(v_e, array['João Silva', 'João Silva']);
  if (v_res->>'quantidade_criada')::int <> 2 then raise exception 'G: duplicados deveriam criar 2'; end if;
  select count(*) into v_n from public.lista_vip lv where lv.evento_id = v_e and lv.nome = 'João Silva';
  if v_n <> 3 then raise exception 'G: deveria haver 3 "João Silva" (1 + 2), obtido %', v_n; end if;

  -- D) lista vazia rejeitada
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e, array[]::text[]);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'D: lista vazia deveria falhar'; end if;

  -- E) mais de 100 rejeitado
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e, array(select 'P' || g from generate_series(1, 101) g));
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'E: mais de 100 deveria falhar'; end if;

  -- F) nome vazio rejeitado
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e, array['Nome Ok', '   ']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'F: nome vazio deveria falhar'; end if;

  -- H) evento inexistente
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(gen_random_uuid(), array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'H: evento inexistente deveria falhar'; end if;

  -- I) evento CANCELADO
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e_cancel, array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'I: evento CANCELADO deveria falhar'; end if;

  -- N) atomicidade: um nome invalido -> nenhum criado
  select count(*) into v_n from public.lista_vip lv where lv.evento_id = v_e;
  v_falhou := false;
  begin
    perform public.criar_lista_vip_em_lote_admin(v_e, array['Novo 1', 'Novo 2', '  ']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'N: deveria falhar com nome invalido'; end if;
  select count(*) into v_qtd from public.lista_vip lv where lv.evento_id = v_e;
  if v_qtd <> v_n then raise exception 'N: operacao deveria ser atomica (antes=%, depois=%)', v_n, v_qtd; end if;

  -- O) auditoria
  select count(*) into v_n from public.auditoria a
   where a.acao = 'VIP_LOTE_ADICIONADO'
     and a.entidade = 'lista_vip'
     and a.entidade_id = v_e
     and a.usuario_id = v_admin
     and (a.dados_novos->>'quantidade') is not null;
  if v_n <> 2 then raise exception 'O: esperado 2 auditorias VIP_LOTE_ADICIONADO (obtido %)', v_n; end if;

  -- P) busca da portaria encontra convidados criados
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_res := public.buscar_ingressos_por_nome(v_e, 'Carlos Ferreira');
  if not exists (
    select 1 from jsonb_array_elements(v_res) el
     where el->>'origem' = 'VIP' and el->>'participante_nome' = 'Carlos Ferreira'
  ) then
    raise exception 'P: busca da portaria deveria encontrar o convidado em lote';
  end if;
end $$;

select 'lista_vip_lote: todos os testes passaram' as resultado;

rollback;
