-- =============================================================================
-- GZ1 Ingresso - Testes: lotes administrativos (listar_lotes_admin / criar_lote_admin)
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

-- A) anon sem EXECUTE ---------------------------------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.listar_lotes_admin(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_lotes_admin';
  end if;
  if has_function_privilege('anon',
       'public.criar_lote_admin(uuid,text,integer,numeric,public.tipo_ativacao_lote,timestamptz)'::regprocedure,
       'EXECUTE') then
    raise exception 'A: anon nao pode executar criar_lote_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();
  v_evento uuid := gen_random_uuid();
  v_res jsonb;
  v_lote1 uuid;
  v_lote2 uuid;
  v_lote3 uuid;
  v_ordem integer;
  v_ativacao timestamptz;
  v_local text;
  v_qtd_vend integer;
  v_qtd_disp integer;
  v_pedido uuid := gen_random_uuid();
begin
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Lotes', 'adminlotes_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Lotes', 'portlotes_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Lotes Teste', 'evento-lotes-' || replace(v_evento::text,'-',''), now() + interval '20 days',
          'Galeria', 'Rua 1', 500, 100, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  -- B) PORTARIA negado (listar e criar)
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  begin
    perform public.listar_lotes_admin(v_evento);
    raise exception 'B: PORTARIA nao deveria listar';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B(listar): %', sqlerrm; end if;
  end;
  begin
    perform public.criar_lote_admin(v_evento, 'X', 10, 50, 'MANUAL', null);
    raise exception 'B: PORTARIA nao deveria criar';
  exception when others then
    if position('permiss' in lower(sqlerrm)) = 0 then raise exception 'B(criar): %', sqlerrm; end if;
  end;

  -- ADMIN
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- C) ADMIN lista (evento real, sem lotes)
  v_res := public.listar_lotes_admin(v_evento);
  if (v_res->'evento'->>'evento_id')::uuid <> v_evento then raise exception 'C: evento incorreto'; end if;
  if jsonb_array_length(v_res->'lotes') <> 0 then raise exception 'C: deveria estar vazio'; end if;

  -- D/E) cria lote 1 (MANUAL) e ordem automatica
  v_res := public.criar_lote_admin(v_evento, 'Lote 1', 10, 50, 'MANUAL', null);
  v_lote1 := (v_res->>'lote_id')::uuid;
  v_ordem := (v_res->>'ordem')::int;
  if v_lote1 is null then raise exception 'D: lote_id ausente'; end if;
  if v_ordem <> 1 then raise exception 'E: primeira ordem deveria ser 1 (veio %)', v_ordem; end if;

  -- H/L) MANUAL => ativacao_em null e nasce INATIVO
  select ativacao_em, status into v_ativacao, v_local from public.lotes where id = v_lote1;
  if v_ativacao is not null then raise exception 'H: MANUAL deveria ter ativacao_em null'; end if;
  if v_local <> 'INATIVO' then raise exception 'L: primeiro lote deveria nascer INATIVO'; end if;

  -- E/M) cria lote 2 (ESGOTAMENTO) => ordem 2, INATIVO
  v_res := public.criar_lote_admin(v_evento, 'Lote 2', 20, 70, 'ESGOTAMENTO', null);
  v_lote2 := (v_res->>'lote_id')::uuid;
  if (v_res->>'ordem')::int <> 2 then raise exception 'E: segunda ordem deveria ser 2'; end if;
  select ativacao_em, status into v_ativacao, v_local from public.lotes where id = v_lote2;
  if v_ativacao is not null then raise exception 'I: ESGOTAMENTO deveria ter ativacao_em null'; end if;
  if v_local <> 'INATIVO' then raise exception 'M: segundo lote deveria ser INATIVO'; end if;

  -- K) DATA_HORA com horario America/Sao_Paulo (20:00 local => 23:00Z)
  v_res := public.criar_lote_admin(v_evento, 'Lote 3', 30, 90, 'DATA_HORA', '2026-10-29T23:00:00Z');
  v_lote3 := (v_res->>'lote_id')::uuid;
  select to_char(ativacao_em at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
    into v_local from public.lotes where id = v_lote3;
  if v_local <> '2026-10-29 20:00' then raise exception 'K: timezone incorreto (%)', v_local; end if;

  -- J) DATA_HORA sem ativacao_em => erro controlado
  begin
    perform public.criar_lote_admin(v_evento, 'Lote X', 10, 10, 'DATA_HORA', null);
    raise exception 'J: DATA_HORA sem ativacao_em deveria falhar';
  exception when others then
    if position('data e hora' in lower(sqlerrm)) = 0 then raise exception 'J: %', sqlerrm; end if;
  end;

  -- F) quantidade invalida
  begin
    perform public.criar_lote_admin(v_evento, 'Qtd', 0, 10, 'MANUAL', null);
    raise exception 'F: quantidade 0 deveria falhar';
  exception when others then
    if position('quantidade' in lower(sqlerrm)) = 0 then raise exception 'F: %', sqlerrm; end if;
  end;

  -- G) preco invalido
  begin
    perform public.criar_lote_admin(v_evento, 'Preco', 10, -1, 'MANUAL', null);
    raise exception 'G: preco negativo deveria falhar';
  exception when others then
    if position('preco' in lower(sqlerrm)) = 0 then raise exception 'G: %', sqlerrm; end if;
  end;

  -- Q) evento inexistente
  begin
    perform public.listar_lotes_admin(gen_random_uuid());
    raise exception 'Q: evento inexistente deveria falhar (listar)';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'Q(listar): %', sqlerrm; end if;
  end;
  begin
    perform public.criar_lote_admin(gen_random_uuid(), 'X', 10, 10, 'MANUAL', null);
    raise exception 'Q: evento inexistente deveria falhar (criar)';
  exception when others then
    if position('nao encontrado' in lower(sqlerrm)) = 0 then raise exception 'Q(criar): %', sqlerrm; end if;
  end;

  -- P) vendidos/disponiveis reais
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em)
  values (v_pedido, v_evento, v_lote1, 'TST' || substr(replace(v_pedido::text,'-',''),1,10), 'Comprador', '11999999999', 2, 'LOTE', 50, 100, 'PAGO', now() + interval '1 day');
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status) values
    (v_pedido, v_evento, v_lote1, 'TST' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'A', 'P1', 50, gen_random_uuid()::text, 'VALIDO'),
    (v_pedido, v_evento, v_lote1, 'TST' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'B', 'P2', 50, gen_random_uuid()::text, 'VALIDO');

  v_res := public.listar_lotes_admin(v_evento);
  select (l->>'quantidade_vendida')::int, (l->>'quantidade_disponivel')::int
    into v_qtd_vend, v_qtd_disp
    from jsonb_array_elements(v_res->'lotes') l
   where (l->>'lote_id')::uuid = v_lote1;
  if v_qtd_vend <> 2 then raise exception 'P: vendidos deveria ser 2 (%)', v_qtd_vend; end if;
  if v_qtd_disp <> 8 then raise exception 'P: disponiveis deveria ser 8 (%)', v_qtd_disp; end if;
  if (v_res->'evento'->>'vendidos')::int <> 2 then raise exception 'P: evento vendidos deveria ser 2'; end if;

  -- N) ativacao manual usa a regra existente
  perform public.ativar_lote_manual(v_lote1);
  select status into v_local from public.lotes where id = v_lote1;
  if v_local <> 'ATIVO' then raise exception 'N: lote1 deveria estar ATIVO'; end if;

  -- O) apenas um lote ATIVO (ativar lote2 encerra lote1)
  perform public.ativar_lote_manual(v_lote2);
  select status into v_local from public.lotes where id = v_lote1;
  if v_local <> 'ENCERRADO' then raise exception 'O: lote1 deveria estar ENCERRADO'; end if;
  if (select count(*) from public.lotes where evento_id = v_evento and status = 'ATIVO') <> 1 then
    raise exception 'O: deveria haver exatamente um lote ATIVO';
  end if;
end $$;

select 'lotes_admin: todos os testes passaram' as resultado;

rollback;
