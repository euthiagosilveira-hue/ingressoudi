-- =============================================================================
-- GZ1 Ingresso - Testes: vendas do evento + ativacao de lote (regra de dominio)
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

-- H) anon sem EXECUTE ---------------------------------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.definir_vendas_evento_admin(uuid, public.status_vendas)'::regprocedure, 'EXECUTE') then
    raise exception 'H: anon nao pode executar definir_vendas_evento_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_lote1 uuid := gen_random_uuid();
  v_lote2 uuid := gen_random_uuid();
  v_res jsonb;
  v_status text;
  v_msg text;
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Vendas', 'adminvendas_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Vendas', 'portvendas_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  -- Evento com vendas ENCERRADAS
  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Vendas', 'evento-vendas-' || replace(v_evento::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 1', 500, 100, 'AGENDADO', 'ENCERRADAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote1, v_evento, 'Lote 1', 1, 10, 50, 'MANUAL', 'INATIVO'),
         (v_lote2, v_evento, 'Lote 2', 2, 20, 70, 'MANUAL', 'INATIVO');

  -- G) PORTARIA negado
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.definir_vendas_evento_admin(v_evento, 'ABERTAS');
    raise exception 'G: PORTARIA nao deveria alterar vendas';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'G(vendas): %', sqlerrm; end if;
  end;
  begin
    perform public.ativar_lote_manual(v_lote1);
    raise exception 'G: PORTARIA nao deveria ativar lote';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'G(ativar): %', sqlerrm; end if;
  end;

  -- ADMIN
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- A/B) vendas ENCERRADAS => ativacao negada com mensagem de dominio
  begin
    perform public.ativar_lote_manual(v_lote1);
    raise exception 'A: ativacao deveria ser negada com vendas encerradas';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if position('vendas encerradas' in lower(v_msg)) = 0 then raise exception 'B: mensagem inesperada: %', v_msg; end if;
  end;

  -- F) ADMIN abre as vendas
  v_res := public.definir_vendas_evento_admin(v_evento, 'ABERTAS');
  if (v_res->>'vendas_status') <> 'ABERTAS' then raise exception 'F: vendas deveriam estar ABERTAS'; end if;

  -- C) com vendas ABERTAS a ativacao e permitida
  perform public.ativar_lote_manual(v_lote1);
  select status into v_status from public.lotes where id = v_lote1;
  if v_status <> 'ATIVO' then raise exception 'C: lote1 deveria estar ATIVO'; end if;

  -- D) apenas um ATIVO
  if (select count(*) from public.lotes where evento_id = v_evento and status = 'ATIVO') <> 1 then
    raise exception 'D: deveria haver exatamente um lote ATIVO';
  end if;

  -- E) lote anterior encerrado conforme dominio
  perform public.ativar_lote_manual(v_lote2);
  select status into v_status from public.lotes where id = v_lote1;
  if v_status <> 'ENCERRADO' then raise exception 'E: lote1 deveria estar ENCERRADO'; end if;
  if (select count(*) from public.lotes where evento_id = v_evento and status = 'ATIVO') <> 1 then
    raise exception 'D: deveria continuar havendo apenas um lote ATIVO';
  end if;

  -- transicoes permitidas: fechar vendas
  v_res := public.definir_vendas_evento_admin(v_evento, 'ENCERRADAS');
  if (v_res->>'vendas_status') <> 'ENCERRADAS' then raise exception 'transicao: deveria ENCERRAR'; end if;

  -- transicoes proibidas: evento REALIZADO/CANCELADO
  update public.eventos set status = 'REALIZADO' where id = v_evento;
  begin
    perform public.definir_vendas_evento_admin(v_evento, 'ABERTAS');
    raise exception 'transicao: REALIZADO nao deveria permitir';
  exception when others then
    if position('nao permite' in lower(sqlerrm)) = 0 then raise exception 'transicao(REALIZADO): %', sqlerrm; end if;
  end;
  update public.eventos set status = 'CANCELADO' where id = v_evento;
  begin
    perform public.definir_vendas_evento_admin(v_evento, 'ABERTAS');
    raise exception 'transicao: CANCELADO nao deveria permitir';
  exception when others then
    if position('nao permite' in lower(sqlerrm)) = 0 then raise exception 'transicao(CANCELADO): %', sqlerrm; end if;
  end;
end $$;

select 'vendas_evento_admin: todos os testes passaram' as resultado;

rollback;
