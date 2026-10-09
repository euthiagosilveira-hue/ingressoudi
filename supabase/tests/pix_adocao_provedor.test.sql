-- =============================================================================
-- GZ1 Ingresso - Testes: adocao de provedor Pix em pagamento pendente
-- Executar como owner. begin/rollback.
-- =============================================================================

begin;

do $$
declare
  v_evento uuid := gen_random_uuid();
  v_lote uuid := gen_random_uuid();
  v_p1 uuid := gen_random_uuid();
  v_p2 uuid := gen_random_uuid();
  v_p3 uuid := gen_random_uuid();
  v_p4 uuid := gen_random_uuid();
  v_p5 uuid := gen_random_uuid();
  v_tok2 uuid := gen_random_uuid();
  v_tok3 uuid := gen_random_uuid();
  v_tok4 uuid := gen_random_uuid();
  v_tok5 uuid := gen_random_uuid();
  v_res jsonb;
  v_outro jsonb;
  v_prov text;
begin
  insert into public.eventos (id, nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, vendas_status, publicacao_status)
  values (v_evento, 'Evento Pix', 'evento-pix-' || replace(v_evento::text,'-',''), now() + interval '30 days',
          'Galeria', 'Rua 1', 1000, 1000, 'AGENDADO', 'ABERTAS', 'PUBLICADO');

  insert into public.lotes (id, evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_lote, v_evento, 'Lote 1', 1, 100, 30, 'MANUAL', 'ATIVO');

  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em, checkout_token)
  values
    (v_p1, v_evento, v_lote, 'PX' || replace(v_p1::text,'-',''), 'A', '11999999991', 1, 'LOTE', 30, 30, 'RESERVADO', now() + interval '30 min', gen_random_uuid()),
    (v_p2, v_evento, v_lote, 'PX' || replace(v_p2::text,'-',''), 'B', '11999999992', 1, 'LOTE', 30, 30, 'RESERVADO', now() + interval '30 min', v_tok2),
    (v_p3, v_evento, v_lote, 'PX' || replace(v_p3::text,'-',''), 'C', '11999999993', 1, 'LOTE', 30, 30, 'RESERVADO', now() + interval '30 min', v_tok3),
    (v_p4, v_evento, v_lote, 'PX' || replace(v_p4::text,'-',''), 'D', '11999999994', 1, 'LOTE', 30, 30, 'RESERVADO', now() - interval '1 min', v_tok4);

  -- A) legado STONE PENDENTE sem cobranca -> adota MERCADO_PAGO
  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status)
  values (v_p1, 'STONE', 30, now() + interval '30 min', 'PENDENTE');
  v_res := public.criar_pagamento_pendente_por_token(
    (select checkout_token from public.pedidos where id = v_p1),
    'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
  if (v_res->>'provedor') <> 'MERCADO_PAGO' then raise exception 'A: provedor nao adotado (%)', v_res->>'provedor'; end if;
  select provedor into v_prov from public.pagamentos where pedido_id = v_p1;
  if v_prov <> 'MERCADO_PAGO' then raise exception 'A: linha nao atualizada'; end if;

  -- B) STONE com cobranca externa -> conflito
  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status, cobranca_id)
  values (v_p2, 'STONE', 30, now() + interval '30 min', 'PENDENTE', 'ORD-EXISTENTE');
  begin
    perform public.criar_pagamento_pendente_por_token(v_tok2, 'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
    raise exception 'B: deveria recusar troca de provedor com cobranca';
  exception when others then
    if position('outro provedor' in lower(sqlerrm)) = 0 then raise exception 'B: %', sqlerrm; end if;
  end;

  -- C) MERCADO_PAGO existente -> reutiliza
  insert into public.pagamentos (pedido_id, provedor, valor, expira_em, status)
  values (v_p3, 'MERCADO_PAGO', 30, now() + interval '30 min', 'PENDENTE');
  v_res := public.criar_pagamento_pendente_por_token(v_tok3, 'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
  if (v_res->>'reutilizado')::boolean is not true then raise exception 'C: deveria reutilizar'; end if;
  if (v_res->>'provedor') <> 'MERCADO_PAGO' then raise exception 'C: provedor incorreto'; end if;

  -- D) novo pagamento (sem existente) nasce MERCADO_PAGO
  insert into public.pedidos (id, evento_id, lote_id, codigo, comprador_nome, comprador_telefone, quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em, checkout_token)
  values (v_p5, v_evento, v_lote, 'PX' || replace(v_p5::text,'-',''), 'E', '11999999995', 1, 'LOTE', 30, 30, 'RESERVADO', now() + interval '30 min', v_tok5);
  v_res := public.criar_pagamento_pendente_por_token(v_tok5, 'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
  if (v_res->>'provedor') <> 'MERCADO_PAGO' then raise exception 'D: provedor incorreto'; end if;
  if (v_res->>'status') <> 'PENDENTE' then raise exception 'D: status deveria ser PENDENTE'; end if;

  -- F) idempotencia: segunda chamada devolve o mesmo pagamento
  v_outro := public.criar_pagamento_pendente_por_token(v_tok5, 'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
  if v_outro->>'pagamento_id' <> v_res->>'pagamento_id' then raise exception 'F: ids diferentes'; end if;
  if (v_outro->>'reutilizado')::boolean is not true then raise exception 'F: deveria reutilizar'; end if;

  -- E) reserva expirada (novo pagamento) -> erro
  begin
    perform public.criar_pagamento_pendente_por_token(v_tok4, 'MERCADO_PAGO'::public.provedor_pagamento, null, null, null);
    raise exception 'E: reserva expirada deveria falhar';
  exception when others then
    if position('expirada' in lower(sqlerrm)) = 0 then raise exception 'E: %', sqlerrm; end if;
  end;
end $$;

select 'pix_adocao_provedor: todos os testes passaram' as resultado;

rollback;
