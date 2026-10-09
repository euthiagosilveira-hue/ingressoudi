-- =============================================================================
-- GZ1 Ingresso - Checkout publico seguro (checkout_token)
-- Migration: checkout_publico_seguro
--
-- Objetivo: recuperar reserva e criar pagamento PENDENTE a partir de um token
-- opaco (bearer) do checkout anonimo, sem expor pedido_id.
--
-- Escopo:
--   * public.pedidos.checkout_token uuid (unico, imprevisivel, backfill)
--   * private.criar_reserva passa a retornar checkout_token
--   * public/private.obter_checkout_pedido(token)  (somente dados de checkout)
--   * public/private.criar_pagamento_pendente_por_token(token, ...) idempotente
--   * hardening: criar_pagamento_pendente(pedido_id,...) deixa de ser acessivel
--     a anon/authenticated (mantido para service_role)
--
-- NAO integra providers externos, NAO cria Pix, NAO altera RLS/policies.
-- Padrao: public SECURITY INVOKER -> private SECURITY DEFINER, search_path=''.
-- =============================================================================

-- 1) CHECKOUT TOKEN -----------------------------------------------------------
alter table public.pedidos add column if not exists checkout_token uuid;

update public.pedidos
   set checkout_token = gen_random_uuid()
 where checkout_token is null;

alter table public.pedidos alter column checkout_token set default gen_random_uuid();
alter table public.pedidos alter column checkout_token set not null;

create unique index if not exists uq_pedidos_checkout_token
  on public.pedidos (checkout_token);

comment on column public.pedidos.checkout_token is
  'Token opaco (bearer) do checkout publico. Nao expor em listagens/relatorios.';

-- 2) CRIAR RESERVA: retorna checkout_token ------------------------------------
create or replace function private.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null
)
returns jsonb
language plpgsql
security definer
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
  v_checkout_token uuid;
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

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    raise exception 'Nenhum lote ATIVO para o evento %', p_evento_id using errcode = '23514';
  end if;

  v_disponivel_evento := private.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
      v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := private.calcular_disponibilidade_lote(v_lote.id);
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
  returning id, checkout_token into v_pedido_id, v_checkout_token;

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

  perform private.processar_virada_lote_esgotamento(p_evento_id);

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
    'checkout_token', v_checkout_token,
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

-- 3) OBTER CHECKOUT PEDIDO ----------------------------------------------------
create or replace function private.obter_checkout_pedido(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pag_json jsonb;
begin
  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

  if v_pedido.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_pedido.lote_id;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;

  if found then
    v_pag_json := jsonb_build_object(
      'pagamento_id', v_pag.id,
      'provedor', v_pag.provedor,
      'status', v_pag.status,
      'valor', v_pag.valor,
      'expira_em', v_pag.expira_em,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa
    );
  else
    v_pag_json := null;
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'quantidade', v_pedido.quantidade,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_total', v_pedido.valor_total,
    'pedido_status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pagamento', v_pag_json
  );
end;
$$;

create or replace function public.obter_checkout_pedido(p_token uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_checkout_pedido(p_token);
$$;

-- 4) CRIAR PAGAMENTO PENDENTE POR TOKEN (idempotente) -------------------------
create or replace function private.criar_pagamento_pendente_por_token(
  p_token uuid,
  p_provider public.provedor_pagamento,
  p_transaction_id text default null,
  p_charge_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pagamento_id uuid;
begin
  if p_provider is null then
    raise exception 'provider obrigatorio' using errcode = '23514';
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   for update;

  if not found then
    raise exception 'Checkout nao encontrado' using errcode = '23503';
  end if;

  -- idempotencia: reutiliza pagamento existente (1:1 por pedido)
  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;
  if found then
    return jsonb_build_object(
      'pagamento_id', v_pag.id,
      'pedido_id', v_pedido.id,
      'provedor', v_pag.provedor,
      'valor', v_pag.valor,
      'status', v_pag.status,
      'expira_em', v_pag.expira_em,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa,
      'reutilizado', true
    );
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', v_pedido.id, v_pedido.status
      using errcode = '23514';
  end if;

  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido expirada' using errcode = '23514';
  end if;

  begin
    insert into public.pagamentos (
      pedido_id, provedor, valor, expira_em,
      transacao_id, cobranca_id, referencia_externa
    ) values (
      v_pedido.id, p_provider, v_pedido.valor_total, v_pedido.reserva_expira_em,
      p_transaction_id, p_charge_id, p_referencia_externa
    )
    returning id into v_pagamento_id;
  exception
    when unique_violation then
      select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;
      return jsonb_build_object(
        'pagamento_id', v_pag.id,
        'pedido_id', v_pedido.id,
        'provedor', v_pag.provedor,
        'valor', v_pag.valor,
        'status', v_pag.status,
        'expira_em', v_pag.expira_em,
        'transacao_id', v_pag.transacao_id,
        'cobranca_id', v_pag.cobranca_id,
        'referencia_externa', v_pag.referencia_externa,
        'reutilizado', true
      );
  end;

  return jsonb_build_object(
    'pagamento_id', v_pagamento_id,
    'pedido_id', v_pedido.id,
    'provedor', p_provider,
    'valor', v_pedido.valor_total,
    'status', 'PENDENTE',
    'expira_em', v_pedido.reserva_expira_em,
    'transacao_id', p_transaction_id,
    'cobranca_id', p_charge_id,
    'referencia_externa', p_referencia_externa,
    'reutilizado', false
  );
end;
$$;

create or replace function public.criar_pagamento_pendente_por_token(
  p_token uuid,
  p_provider public.provedor_pagamento,
  p_transaction_id text default null,
  p_charge_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_pagamento_pendente_por_token(
    p_token, p_provider, p_transaction_id, p_charge_id, p_referencia_externa
  );
$$;

-- 5) ACL ----------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;

-- obter_checkout_pedido (anon pode ler o proprio checkout via token)
revoke execute on function public.obter_checkout_pedido(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.obter_checkout_pedido(uuid)
  to anon, authenticated, service_role;

revoke all on function private.obter_checkout_pedido(uuid) from public;
grant execute on function private.obter_checkout_pedido(uuid)
  to anon, authenticated, service_role;

-- criar_pagamento_pendente_por_token (checkout publico)
revoke execute on function public.criar_pagamento_pendente_por_token(
  uuid, public.provedor_pagamento, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.criar_pagamento_pendente_por_token(
  uuid, public.provedor_pagamento, text, text, text
) to anon, authenticated, service_role;

revoke all on function private.criar_pagamento_pendente_por_token(
  uuid, public.provedor_pagamento, text, text, text
) from public;
grant execute on function private.criar_pagamento_pendente_por_token(
  uuid, public.provedor_pagamento, text, text, text
) to anon, authenticated, service_role;

-- HARDENING: criar_pagamento_pendente(pedido_id, ...) deixa de ser publico
revoke execute on function public.criar_pagamento_pendente(
  uuid, public.provedor_pagamento, text, text, text
) from public, anon, authenticated;
grant execute on function public.criar_pagamento_pendente(
  uuid, public.provedor_pagamento, text, text, text
) to service_role;

revoke all on function private.criar_pagamento_pendente(
  uuid, public.provedor_pagamento, text, text, text
) from public, anon, authenticated;
grant execute on function private.criar_pagamento_pendente(
  uuid, public.provedor_pagamento, text, text, text
) to service_role;
