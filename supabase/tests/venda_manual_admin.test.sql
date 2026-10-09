-- =============================================================================
-- GZ1 Ingresso - Testes: venda manual em dinheiro (ADMINISTRADOR)
-- Arquivo: supabase/tests/venda_manual_admin.test.sql
-- Executar como owner. begin/rollback.
--
-- Cobre:
--   A anon negado
--   B PORTARIA negado
--   C ADMIN vende
--   D evento inexistente
--   E lote inexistente
--   F lote de outro evento rejeitado
--   G lote INATIVO rejeitado
--   H lote ENCERRADO rejeitado
--   I CANCELADO rejeitado
--   J REALIZADO rejeitado
--   K quantidade 0 rejeitada
--   L quantidade >10 rejeitada
--   M estoque insuficiente rejeitado
--   N preco sempre vem do lote
--   O pedido nasce PAGO
--   P pagamento nasce APROVADO/DINHEIRO
--   Q ingresso nasce VALIDO
--   R QR unico
--   S valor historico correto
--   T disponibilidade diminui
--   U concorrencia nao gera estoque negativo
--   V auditoria criada
--   W nenhum provider externo envolvido
--   X vendas_status ENCERRADAS nao bloqueia venda manual (EM_ANDAMENTO)
-- =============================================================================

begin;

-- A) anon nao pode executar a RPC
do $$
begin
  if has_function_privilege(
    'anon',
    'public.criar_venda_manual_admin(uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric)',
    'EXECUTE'
  ) then
    raise exception 'A: anon nao pode executar criar_venda_manual_admin';
  end if;
  if has_function_privilege('anon', 'public.listar_eventos_venda_manual_admin()', 'EXECUTE') then
    raise exception 'A: anon nao pode executar listar_eventos_venda_manual_admin';
  end if;
end $$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_portaria uuid := gen_random_uuid();

  v_e1 uuid; v_l1 uuid;                 -- AGENDADO/ABERTAS, lote ATIVO
  v_e2 uuid; v_l2 uuid;                 -- outro evento, lote ATIVO
  v_e_inativo uuid; v_l_inativo uuid;   -- lote INATIVO
  v_e_encerrado uuid; v_l_encerrado uuid; -- lote ENCERRADO
  v_e_cancel uuid; v_l_cancel uuid;     -- evento CANCELADO
  v_e_real uuid; v_l_real uuid;         -- evento REALIZADO
  v_e_em uuid; v_l_em uuid;             -- EM_ANDAMENTO + vendas ENCERRADAS

  v_res jsonb;
  v_ped uuid;
  v_pag uuid;
  v_msg text;
  v_falhou boolean;
  v_n integer;
  v_disp_antes integer;
  v_disp_depois integer;
  v_qr1 text;
  v_qr2 text;
  v_vu numeric;
  v_vt numeric;
  v_status text;
  v_prov text;
  v_e30 uuid; v_l30 uuid;
  v_base numeric;
  v_apos numeric;
  v_fin jsonb;
  v_dash jsonb;
begin
  -- -------------------------------------------------------------------------
  -- Fixtures
  -- -------------------------------------------------------------------------
  insert into auth.users (id) values (v_admin), (v_portaria);
  insert into public.usuarios (id, nome, email, perfil, ativo) values
    (v_admin, 'Admin Venda', 'adminvenda_' || replace(v_admin::text,'-','') || '@test.local', 'ADMINISTRADOR', true),
    (v_portaria, 'Port Venda', 'portvenda_' || replace(v_portaria::text,'-','') || '@test.local', 'PORTARIA', true);

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Venda','venda-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,5,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e1;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e1,'Lote Venda',1,5,37.50,'MANUAL','ATIVO') returning id into v_l1;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Outro','outro-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e2;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e2,'Lote Outro',1,10,10.00,'MANUAL','ATIVO') returning id into v_l2;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Inativo','inativo-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_inativo;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_inativo,'Lote Inativo',1,10,10.00,'MANUAL','INATIVO') returning id into v_l_inativo;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Encerrado','encerr-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e_encerrado;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_encerrado,'Lote Encerrado',1,10,10.00,'MANUAL','ENCERRADO') returning id into v_l_encerrado;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Cancelado','cancel-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',100,10,'CANCELADO','PUBLICADO','ABERTAS')
  returning id into v_e_cancel;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_cancel,'Lote Cancel',1,10,10.00,'MANUAL','ATIVO') returning id into v_l_cancel;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Realizado','real-'||replace(gen_random_uuid()::text,'-',''), now()-interval '2 days','L','E',100,10,'REALIZADO','PUBLICADO','ENCERRADAS')
  returning id into v_e_real;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_real,'Lote Real',1,10,10.00,'MANUAL','ATIVO') returning id into v_l_real;

  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Andamento','andam-'||replace(gen_random_uuid()::text,'-',''), now()-interval '1 hour','L','E',100,10,'EM_ANDAMENTO','PUBLICADO','ENCERRADAS')
  returning id into v_e_em;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e_em,'Lote Andamento',1,10,20.00,'MANUAL','ATIVO') returning id into v_l_em;

  -- -------------------------------------------------------------------------
  -- B) PORTARIA negado
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_portaria::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_portaria::text, true);
  v_falhou := false; v_msg := null;
  begin
    perform public.criar_venda_manual_admin(v_e1, v_l1, 'Port', '11999990000', array['P']);
  exception when others then
    v_falhou := true; v_msg := sqlerrm;
  end;
  if not v_falhou then raise exception 'B: PORTARIA nao deveria vender'; end if;
  if position('permiss' in lower(v_msg)) = 0 then raise exception 'B: erro inesperado: %', v_msg; end if;

  -- -------------------------------------------------------------------------
  -- C) ADMIN vende 2 (quantidade, preco, pedido, pagamento, ingressos)
  -- -------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  select private.calcular_disponibilidade_lote(v_l1) into v_disp_antes;

  v_res := public.criar_venda_manual_admin(v_e1, v_l1, 'Comprador Teste', '11999990000', array['Ana Venda','Bia Venda']);
  v_ped := (v_res->>'pedido_id')::uuid;
  v_pag := (v_res->>'pagamento_id')::uuid;

  if (v_res->>'quantidade')::int <> 2 then raise exception 'C: quantidade deveria ser 2'; end if;
  if (v_res->>'status') <> 'PAGO' then raise exception 'C: status deveria ser PAGO'; end if;
  if (v_res->>'forma') <> 'DINHEIRO' then raise exception 'C: forma deveria ser DINHEIRO'; end if;
  if v_res ? 'checkout_token' then raise exception 'C: checkout_token nao deve ser exposto'; end if;

  select private.calcular_disponibilidade_lote(v_l1) into v_disp_depois;

  -- -------------------------------------------------------------------------
  -- D) evento inexistente
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(gen_random_uuid(), v_l1, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'D: evento inexistente deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- E) lote inexistente
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e1, gen_random_uuid(), 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'E: lote inexistente deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- F) lote de outro evento
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e1, v_l2, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'F: lote de outro evento deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- G) lote INATIVO
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_inativo, v_l_inativo, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'G: lote INATIVO deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- H) lote ENCERRADO
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_encerrado, v_l_encerrado, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'H: lote ENCERRADO deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- I) evento CANCELADO
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_cancel, v_l_cancel, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'I: evento CANCELADO deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- J) evento REALIZADO
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e_real, v_l_real, 'X', '11999990000', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'J: evento REALIZADO deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- K) quantidade 0
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e1, v_l1, 'X', '11999990000', array[]::text[]);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'K: quantidade 0 deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- L) quantidade > 10
  -- -------------------------------------------------------------------------
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(
      v_e1, v_l1, 'X', '11999990000',
      array(select 'P' || g from generate_series(1, 11) g)
    );
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'L: quantidade 11 deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- M) estoque insuficiente (disponivel=3, tentar 5)
  -- -------------------------------------------------------------------------
  if v_disp_depois <> 3 then raise exception 'M: disponibilidade apos C deveria ser 3 (obtido %)', v_disp_depois; end if;
  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(
      v_e1, v_l1, 'X', '11999990000',
      array(select 'P' || g from generate_series(1, 5) g)
    );
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'M: estoque insuficiente deveria falhar'; end if;

  -- -------------------------------------------------------------------------
  -- N/O/P/Q/S/W) verificacoes do pedido criado em C
  -- -------------------------------------------------------------------------
  select p.status into v_status from public.pedidos p where p.id = v_ped;
  if v_status <> 'PAGO' then raise exception 'O: pedido deveria nascer PAGO (obtido %)', v_status; end if;

  -- reserva_expira_em NULL (sem reserva)
  if (select p.reserva_expira_em from public.pedidos p where p.id = v_ped) is not null then
    raise exception 'O: reserva_expira_em deveria ser NULL em venda manual';
  end if;

  select pg.provedor, pg.status into v_prov, v_status
    from public.pagamentos pg where pg.id = v_pag;
  if v_prov <> 'DINHEIRO' then raise exception 'P: provedor deveria ser DINHEIRO (obtido %)', v_prov; end if;
  if v_status <> 'APROVADO' then raise exception 'P: pagamento deveria ser APROVADO (obtido %)', v_status; end if;

  -- N) preco vem do lote (37.50)
  select p.valor_unitario, p.valor_total into v_vu, v_vt
    from public.pedidos p where p.id = v_ped;
  if v_vu <> 37.50 then raise exception 'N: valor_unitario deveria ser 37.50 (obtido %)', v_vu; end if;
  if v_vt <> 75.00 then raise exception 'N: valor_total deveria ser 75.00 (obtido %)', v_vt; end if;

  -- Q/S) ingressos VALIDO com valor historico
  select count(*) into v_n from public.ingressos i
   where i.pedido_id = v_ped and i.status = 'VALIDO' and i.valor_unitario = 37.50;
  if v_n <> 2 then raise exception 'Q/S: deveria haver 2 ingressos VALIDO com valor 37.50 (obtido %)', v_n; end if;

  -- R) QR unico e nao nulo
  select count(distinct i.qr_token) into v_n
    from public.ingressos i where i.pedido_id = v_ped;
  if v_n <> 2 then raise exception 'R: qr_token deveria ser unico por ingresso (obtido %)', v_n; end if;
  if exists (select 1 from public.ingressos i where i.pedido_id = v_ped and (i.qr_token is null or btrim(i.qr_token) = '')) then
    raise exception 'R: qr_token nao pode ser nulo/vazio';
  end if;

  -- W) nenhum dado de provider externo
  if exists (
    select 1 from public.pagamentos pg
     where pg.id = v_pag
       and (pg.transacao_id is not null or pg.cobranca_id is not null
            or pg.referencia_externa is not null or pg.pix_copia_cola is not null
            or pg.pix_qr_code is not null)
  ) then
    raise exception 'W: pagamento em dinheiro nao deve ter dados de provider/PIX';
  end if;

  -- T) disponibilidade diminuiu de 5 para 3
  if v_disp_antes <> 5 then raise exception 'T: disponibilidade antes deveria ser 5 (obtido %)', v_disp_antes; end if;
  if v_disp_depois <> 3 then raise exception 'T: disponibilidade depois deveria ser 3 (obtido %)', v_disp_depois; end if;

  -- V) auditoria criada
  select count(*) into v_n from public.auditoria a
   where a.acao = 'VENDA_MANUAL_CRIADA'
     and a.entidade = 'pedidos'
     and a.entidade_id = v_ped
     and a.usuario_id = v_admin
     and (a.dados_novos->>'forma') = 'DINHEIRO';
  if v_n <> 1 then raise exception 'V: auditoria VENDA_MANUAL_CRIADA ausente/incorreta'; end if;

  -- -------------------------------------------------------------------------
  -- U) concorrencia: vender exatamente o restante (3) e depois 1 deve falhar
  -- -------------------------------------------------------------------------
  v_res := public.criar_venda_manual_admin(
    v_e1, v_l1, 'Comprador Fim', '11999990001', array['C1','C2','C3']
  );
  select private.calcular_disponibilidade_lote(v_l1) into v_n;
  if v_n <> 0 then raise exception 'U: disponibilidade deveria zerar (obtido %)', v_n; end if;

  v_falhou := false;
  begin
    perform public.criar_venda_manual_admin(v_e1, v_l1, 'Excedente', '11999990002', array['X']);
  exception when others then v_falhou := true; end;
  if not v_falhou then raise exception 'U: venda acima do estoque deveria falhar'; end if;

  select count(*) into v_n from public.ingressos i
   where i.lote_id = v_l1 and i.status in ('VALIDO', 'UTILIZADO');
  if v_n <> 5 then raise exception 'U: total vendido no lote deveria ser 5 (obtido %)', v_n; end if;

  -- -------------------------------------------------------------------------
  -- X) vendas_status ENCERRADAS + EM_ANDAMENTO permite venda manual
  -- -------------------------------------------------------------------------
  v_res := public.criar_venda_manual_admin(v_e_em, v_l_em, 'Comprador Andamento', '11999990003', array['A1','A2']);
  if (v_res->>'status') <> 'PAGO' then raise exception 'X: venda em EM_ANDAMENTO/ENCERRADAS deveria ser PAGO'; end if;
  select pg.provedor into v_prov
    from public.pagamentos pg where pg.id = (v_res->>'pagamento_id')::uuid;
  if v_prov <> 'DINHEIRO' then raise exception 'X: provedor deveria ser DINHEIRO'; end if;

  -- -------------------------------------------------------------------------
  -- Y) financeiro e dashboard contabilizam a venda em dinheiro (R$ 30)
  -- -------------------------------------------------------------------------
  insert into public.eventos (nome, slug, inicio_em, local, endereco, capacidade_total, estoque_antecipado, status, publicacao_status, vendas_status)
  values ('Evento Fin 30','fin30-'||replace(gen_random_uuid()::text,'-',''), now()+interval '2 days','L','E',50,10,'AGENDADO','PUBLICADO','ABERTAS')
  returning id into v_e30;
  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, status)
  values (v_e30,'Lote Fin 30',1,10,30.00,'MANUAL','ATIVO') returning id into v_l30;

  select (public.obter_dashboard_admin()->'metricas'->>'faturamento')::numeric into v_base;

  v_res := public.criar_venda_manual_admin(v_e30, v_l30, 'Comprador 30', '11999990004', array['Baia']);
  if (v_res->>'valor_total')::numeric <> 30.00 then
    raise exception 'Y: total deveria ser 30.00 (obtido %)', v_res->>'valor_total';
  end if;

  select (public.obter_dashboard_admin()->'metricas'->>'faturamento')::numeric into v_apos;
  if v_apos <> v_base + 30.00 then
    raise exception 'Y: dashboard faturamento deveria crescer 30 (antes=%, depois=%)', v_base, v_apos;
  end if;

  v_fin := public.obter_financeiro_admin(p_evento_id => v_e30);
  if (v_fin->'resumo'->>'valorAprovado')::numeric <> 30.00 then
    raise exception 'Y: financeiro valorAprovado deveria ser 30';
  end if;
  if jsonb_array_length(v_fin->'movimentacoes') <> 1 then
    raise exception 'Y: financeiro deveria ter 1 movimentacao';
  end if;
  if (v_fin->'movimentacoes'->0->>'provedor') <> 'DINHEIRO' then
    raise exception 'Y: movimentacao deveria ser DINHEIRO';
  end if;
  if (v_fin->'movimentacoes'->0->>'transacao_id') is not null
     or (v_fin->'movimentacoes'->0->>'cobranca_id') is not null then
    raise exception 'Y: venda em dinheiro nao deve ter cobranca externa';
  end if;
end $$;

select 'venda_manual_admin: todos os testes passaram' as resultado;

rollback;
