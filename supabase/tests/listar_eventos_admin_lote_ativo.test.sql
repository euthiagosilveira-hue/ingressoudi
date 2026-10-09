-- =============================================================================
-- GZ1 Ingresso - Testes: lote ativo na listagem admin de eventos
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_sem_lote uuid := gen_random_uuid();
  v_inativos uuid := gen_random_uuid();
  v_ativo uuid := gen_random_uuid();
  v_lote_ativo uuid := gen_random_uuid();
  v_lote_inativo uuid := gen_random_uuid();
  v_pedido uuid := gen_random_uuid();
  v_json jsonb;
  v_ev jsonb;
begin
  insert into auth.users (id) values (v_admin);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Lista', 'adminlista_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true);

  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status) values
    (v_sem_lote, 'A sem lote', 'a-sem-lote-' || replace(v_sem_lote::text,'-',''), now() + interval '10 days', 'L', 'E', 100, 50, 'AGENDADO', 'ENCERRADAS', 'RASCUNHO'),
    (v_inativos, 'B inativos', 'b-inativos-' || replace(v_inativos::text,'-',''), now() + interval '11 days', 'L', 'E', 100, 50, 'AGENDADO', 'ENCERRADAS', 'RASCUNHO'),
    (v_ativo, 'C ativo', 'c-ativo-' || replace(v_ativo::text,'-',''), now() + interval '12 days', 'L', 'E', 100, 50, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status) values
    (gen_random_uuid(), v_inativos, 'B1', 1, 10, 10, 'MANUAL', 'INATIVO'),
    (gen_random_uuid(), v_inativos, 'B2', 2, 10, 20, 'MANUAL', 'INATIVO'),
    (v_lote_ativo, v_ativo, 'Lote Ativo', 1, 10, 30, 'MANUAL', 'ATIVO'),
    (v_lote_inativo, v_ativo, 'Lote Inativo', 2, 20, 40, 'MANUAL', 'INATIVO');

  -- 2 ingressos vendidos no lote ativo
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em)
  values (v_pedido, v_ativo, v_lote_ativo, 'LA' || substr(replace(v_pedido::text,'-',''),1,10), 'Comprador', '11999999999', 2, 'LOTE', 30, 60, 'PAGO', now() + interval '1 day');
  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status) values
    (v_pedido, v_ativo, v_lote_ativo, 'LA' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'A', 'P1', 30, gen_random_uuid()::text, 'VALIDO'),
    (v_pedido, v_ativo, v_lote_ativo, 'LA' || substr(replace(gen_random_uuid()::text,'-',''),1,12) || 'B', 'P2', 30, gen_random_uuid()::text, 'VALIDO');

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  v_json := public.listar_eventos_admin_filtrado(null, null, null, null);

  -- A) evento sem lote
  select l into v_ev from jsonb_array_elements(v_json) l where (l->>'evento_id')::uuid = v_sem_lote;
  if (v_ev->>'lote_ativo_id') is not null then raise exception 'A: sem lote deveria ser null'; end if;

  -- B) todos inativos
  select l into v_ev from jsonb_array_elements(v_json) l where (l->>'evento_id')::uuid = v_inativos;
  if (v_ev->>'lote_ativo_id') is not null then raise exception 'B: inativos deveriam ser null'; end if;

  -- C/D) um ativo com nome/preco
  select l into v_ev from jsonb_array_elements(v_json) l where (l->>'evento_id')::uuid = v_ativo;
  if (v_ev->>'lote_ativo_id')::uuid <> v_lote_ativo then raise exception 'C: lote ativo incorreto'; end if;
  if (v_ev->>'lote_ativo_nome') <> 'Lote Ativo' then raise exception 'C: nome incorreto'; end if;
  if (v_ev->>'lote_ativo_preco')::numeric <> 30 then raise exception 'D: preco incorreto (%)', v_ev->>'lote_ativo_preco'; end if;

  -- E) vendidos/disponiveis
  if (v_ev->>'lote_ativo_vendidos')::int <> 2 then raise exception 'E: vendidos incorreto (%)', v_ev->>'lote_ativo_vendidos'; end if;
  if (v_ev->>'lote_ativo_disponiveis')::int <> 8 then raise exception 'E: disponiveis incorreto (%)', v_ev->>'lote_ativo_disponiveis'; end if;

  -- F) apenas um lote ativo (campo unico) e ordem correta
  if (v_ev->>'lote_ativo_ordem')::int <> 1 then raise exception 'F: ordem incorreta'; end if;
end $$;

select 'listar_eventos_admin_lote_ativo: todos os testes passaram' as resultado;

rollback;
