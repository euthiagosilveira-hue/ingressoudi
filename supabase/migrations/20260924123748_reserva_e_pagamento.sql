-- =============================================================================
-- GZ1 Ingresso - Reserva e pagamento (operacoes transacionais)
-- Migration: reserva_e_pagamento
--
-- Escopo:
--   * sequence segura para codigo de pedido
--   * funcoes auxiliares de disponibilidade (evento e lote)
--   * RPCs transacionais:
--       - public.criar_reserva(...)
--       - public.criar_pagamento_pendente(...)
--       - public.expirar_reserva(...)
--       - public.confirmar_pagamento(...)
--
-- Fora do escopo: Mercado Pago real, webhook, cron/jobs, virada automatica de
-- lote, portaria, RLS, policies, frontend, auth.
--
-- Linguagem: plpgsql. Seguranca: INVOKER (default), SET search_path = '',
-- objetos qualificados com public. Nao ha DROP/DELETE/TRUNCATE destrutivo.
-- =============================================================================

-- CODIGO DE PEDIDO (sequence) -------------------------------------------------
-- Gera codigos legiveis GZ + numero. nextval e atomico; nao usa count(*).
create sequence public.seq_pedido_codigo as bigint start with 100000 increment by 1;

-- DISPONIBILIDADE (funcoes auxiliares de leitura) -----------------------------
-- Consumo = ingressos VALIDO/UTILIZADO, ou RESERVADO cujo pedido ainda esta
-- RESERVADO e nao expirou. Expirados/cancelados nao consomem.
create or replace function public.calcular_disponibilidade_evento(p_evento_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select e.estoque_antecipado - coalesce((
    select count(*)
      from public.ingressos i
      join public.pedidos p on p.id = i.pedido_id
     where i.evento_id = e.id
       and (
         i.status in ('VALIDO', 'UTILIZADO')
         or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
       )
  ), 0)
  from public.eventos e
  where e.id = p_evento_id;
$$;

create or replace function public.calcular_disponibilidade_lote(p_lote_id uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select l.quantidade - coalesce((
    select count(*)
      from public.ingressos i
      join public.pedidos p on p.id = i.pedido_id
     where i.lote_id = l.id
       and (
         i.status in ('VALIDO', 'UTILIZADO')
         or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
       )
  ), 0)
  from public.lotes l
  where l.id = p_lote_id;
$$;

-- CRIAR RESERVA (RPC) ---------------------------------------------------------
create or replace function public.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_qtd integer;
  v_codigo text;
  v_valor_unitario numeric(10, 2);
  v_valor_total numeric(10, 2);
  v_reserva_expira_em timestamptz;
  v_pedido_id uuid;
  v_disponivel_evento integer;
  v_disponivel_lote integer;
  v_ingressos jsonb;
begin
  if p_nomes_participantes is null then
    raise exception 'Lista de participantes obrigatoria' using errcode = '22004';
  end if;

  v_qtd := cardinality(p_nomes_participantes);

  if v_qtd < 1 or v_qtd > 10 then
    raise exception 'Quantidade de participantes deve estar entre 1 e 10 (recebido %)', v_qtd
      using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes_participantes) as n(nome)
     where n.nome is null or btrim(n.nome) = ''
  ) then
    raise exception 'Nome de participante nao pode ser vazio' using errcode = '23514';
  end if;

  if p_comprador_nome is null or btrim(p_comprador_nome) = '' then
    raise exception 'comprador_nome obrigatorio' using errcode = '23514';
  end if;

  if p_comprador_telefone is null or btrim(p_comprador_telefone) = '' then
    raise exception 'comprador_telefone obrigatorio' using errcode = '23514';
  end if;

  -- lock do evento: serializa reservas concorrentes do mesmo evento
  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status <> 'AGENDADO' then
    raise exception 'Evento % nao esta AGENDADO (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  if v_evento.publicacao_status <> 'PUBLICADO' then
    raise exception 'Evento % nao esta PUBLICADO (publicacao=%)', p_evento_id, v_evento.publicacao_status
      using errcode = '23514';
  end if;

  if v_evento.vendas_status <> 'ABERTAS' then
    raise exception 'Vendas encerradas para o evento % (vendas=%)', p_evento_id, v_evento.vendas_status
      using errcode = '23514';
  end if;

  if now() >= v_evento.inicio_em then
    raise exception 'Evento % ja iniciado', p_evento_id using errcode = '23514';
  end if;

  -- lock do lote ativo
  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    raise exception 'Nenhum lote ATIVO para o evento %', p_evento_id using errcode = '23514';
  end if;

  v_disponivel_evento := public.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
      v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := public.calcular_disponibilidade_lote(v_lote.id);
  if v_disponivel_lote < v_qtd then
    raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)',
      v_disponivel_lote, v_qtd using errcode = '23514';
  end if;

  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
  v_valor_unitario := v_lote.preco;
  v_valor_total := v_lote.preco * v_qtd;
  v_reserva_expira_em := now() + interval '15 minutes';

  insert into public.pedidos (
    evento_id, lote_id, codigo,
    comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total,
    status, reserva_expira_em
  ) values (
    p_evento_id, v_lote.id, v_codigo,
    p_comprador_nome, p_comprador_telefone, p_comprador_email,
    v_qtd, 'LOTE', v_valor_unitario, v_valor_total,
    'RESERVADO', v_reserva_expira_em
  )
  returning id into v_pedido_id;

  insert into public.ingressos (
    pedido_id, evento_id, lote_id, codigo,
    participante_nome, valor_unitario, qr_token, status
  )
  select
    v_pedido_id, p_evento_id, v_lote.id,
    v_codigo || '-' || lpad(t.pos::text, 2, '0'),
    btrim(t.nome),
    v_valor_unitario,
    gen_random_uuid()::text,
    'RESERVADO'
  from unnest(p_nomes_participantes) with ordinality as t(nome, pos);

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome
             ) order by i.codigo
           ),
           '[]'::jsonb
         )
    into v_ingressos
    from public.ingressos i
   where i.pedido_id = v_pedido_id;

  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'codigo_pedido', v_codigo,
    'evento_id', p_evento_id,
    'lote_id', v_lote.id,
    'quantidade', v_qtd,
    'valor_unitario', v_valor_unitario,
    'valor_total', v_valor_total,
    'reserva_expira_em', v_reserva_expira_em,
    'status', 'RESERVADO',
    'ingressos', v_ingressos
  );
end;
$$;

-- CRIAR PAGAMENTO PENDENTE (RPC) ----------------------------------------------
create or replace function public.criar_pagamento_pendente(p_pedido_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pagamento_id uuid;
begin
  select * into v_pedido
    from public.pedidos p
   where p.id = p_pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', p_pedido_id, v_pedido.status
      using errcode = '23514';
  end if;

  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido % expirada', p_pedido_id using errcode = '23514';
  end if;

  if exists (select 1 from public.pagamentos pg where pg.pedido_id = p_pedido_id) then
    raise exception 'Pedido % ja possui pagamento', p_pedido_id using errcode = '23505';
  end if;

  insert into public.pagamentos (pedido_id, valor, expira_em)
  values (p_pedido_id, v_pedido.valor_total, v_pedido.reserva_expira_em)
  returning id into v_pagamento_id;

  return jsonb_build_object(
    'pagamento_id', v_pagamento_id,
    'pedido_id', p_pedido_id,
    'valor', v_pedido.valor_total,
    'status', 'PENDENTE',
    'expira_em', v_pedido.reserva_expira_em
  );
end;
$$;

-- EXPIRAR RESERVA (RPC) -------------------------------------------------------
create or replace function public.expirar_reserva(p_pedido_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_ingressos integer := 0;
  v_pagamentos integer := 0;
begin
  select * into v_pedido
    from public.pedidos p
   where p.id = p_pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  if v_pedido.status = 'EXPIRADO' then
    return jsonb_build_object(
      'pedido_id', p_pedido_id, 'status', 'EXPIRADO', 'resultado', 'ja_expirado'
    );
  end if;

  if v_pedido.status in ('PAGO', 'CANCELADO') then
    return jsonb_build_object(
      'pedido_id', p_pedido_id, 'status', v_pedido.status, 'resultado', 'nao_aplicavel'
    );
  end if;

  if now() < v_pedido.reserva_expira_em then
    return jsonb_build_object(
      'pedido_id', p_pedido_id, 'status', v_pedido.status, 'resultado', 'ainda_valida'
    );
  end if;

  update public.pedidos set status = 'EXPIRADO' where id = p_pedido_id;

  update public.ingressos
     set status = 'EXPIRADO'
   where pedido_id = p_pedido_id
     and status = 'RESERVADO';
  get diagnostics v_ingressos = row_count;

  update public.pagamentos
     set status = 'EXPIRADO'
   where pedido_id = p_pedido_id
     and status = 'PENDENTE';
  get diagnostics v_pagamentos = row_count;

  return jsonb_build_object(
    'pedido_id', p_pedido_id,
    'status', 'EXPIRADO',
    'resultado', 'expirado',
    'ingressos_expirados', v_ingressos,
    'pagamentos_expirados', v_pagamentos
  );
end;
$$;

-- CONFIRMAR PAGAMENTO (RPC) ---------------------------------------------------
create or replace function public.confirmar_pagamento(
  p_pedido_id uuid,
  p_mercado_pago_payment_id text,
  p_mercado_pago_external_reference text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pagamento public.pagamentos%rowtype;
  v_ingressos integer := 0;
begin
  if p_mercado_pago_payment_id is null or btrim(p_mercado_pago_payment_id) = '' then
    raise exception 'mercado_pago_payment_id obrigatorio' using errcode = '23514';
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.id = p_pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  select * into v_pagamento
    from public.pagamentos pg
   where pg.pedido_id = p_pedido_id
   for update;

  if not found then
    raise exception 'Pagamento do pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  -- idempotencia: pedido ja pago e pagamento aprovado
  if v_pedido.status = 'PAGO' and v_pagamento.status = 'APROVADO' then
    if v_pagamento.mercado_pago_payment_id = p_mercado_pago_payment_id then
      return jsonb_build_object(
        'pedido_id', p_pedido_id,
        'pagamento_id', v_pagamento.id,
        'status', 'PAGO',
        'resultado', 'ja_confirmado'
      );
    else
      raise exception 'Pedido % ja pago com outro payment_id', p_pedido_id
        using errcode = '23505';
    end if;
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', p_pedido_id, v_pedido.status
      using errcode = '23514';
  end if;

  -- nao ressuscitar reserva expirada
  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido % expirada', p_pedido_id using errcode = '23514';
  end if;

  if v_pagamento.status <> 'PENDENTE' then
    raise exception 'Pagamento % nao esta PENDENTE (status=%)', v_pagamento.id, v_pagamento.status
      using errcode = '23514';
  end if;

  if v_pagamento.valor <> v_pedido.valor_total then
    raise exception 'Pagamento % valor % difere do total % do pedido',
      v_pagamento.id, v_pagamento.valor, v_pedido.valor_total
      using errcode = '23514';
  end if;

  update public.pagamentos
     set status = 'APROVADO',
         confirmado_em = now(),
         mercado_pago_payment_id = p_mercado_pago_payment_id,
         mercado_pago_external_reference = p_mercado_pago_external_reference
   where id = v_pagamento.id;

  update public.pedidos
     set status = 'PAGO',
         pago_em = now()
   where id = p_pedido_id;

  update public.ingressos
     set status = 'VALIDO'
   where pedido_id = p_pedido_id
     and status = 'RESERVADO';
  get diagnostics v_ingressos = row_count;

  return jsonb_build_object(
    'pedido_id', p_pedido_id,
    'pagamento_id', v_pagamento.id,
    'status', 'PAGO',
    'ingressos_validados', v_ingressos,
    'resultado', 'confirmado'
  );
end;
$$;
