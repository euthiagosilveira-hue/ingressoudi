-- =============================================================================
-- GZ1 Ingresso - Consistencia relacional entre entidades
-- Migration: consistencia_relacional
--
-- Escopo:
--   * funcoes trigger internas de integridade (nao sao RPC/API)
--   * validacoes que cruzam tabelas e nao cabem em CHECK simples
--
-- Regras:
--   PEDIDOS    : lote pertence ao mesmo evento do pedido
--   INGRESSOS  : pedido/evento/lote/valor coerentes + quantidade <= pedido
--   PAGAMENTOS : valor = pedido.valor_total; expira_em = pedido.reserva_expira_em
--   ENTRADAS   : evento = ingresso.evento_id; status do ingresso utilizavel
--   TENTATIVAS : evento = ingresso.evento_id (quando ingresso_id nao nulo)
--   CANCELAMENTOS/REEMBOLSOS : pagamento do mesmo pedido; reembolso <= pago
--
-- Fora do escopo: RLS, policies, RPCs de negocio, views, cron, Mercado Pago.
-- Nao ha DROP, DELETE, TRUNCATE ou ALTER destrutivo.
-- =============================================================================

-- PEDIDOS ---------------------------------------------------------------------
-- Se o pedido aponta para um lote, esse lote deve ser do mesmo evento do pedido.
create or replace function public.validar_pedido_lote_evento()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.lote_id is not null then
    perform 1
      from public.lotes l
     where l.id = new.lote_id
       and l.evento_id = new.evento_id;

    if not found then
      raise exception
        'Pedido % : lote % nao pertence ao evento %',
        new.id, new.lote_id, new.evento_id
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_validar_pedido_lote_evento
  before insert or update of evento_id, lote_id on public.pedidos
  for each row execute function public.validar_pedido_lote_evento();

-- INGRESSOS -------------------------------------------------------------------
-- Coerencia entre ingresso e pedido (evento, lote, valor) e limite de quantidade.
-- A contagem usa SELECT ... FOR UPDATE na linha do pedido para serializar
-- insercoes concorrentes do mesmo pedido.
create or replace function public.validar_ingresso_consistencia()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_evento_id uuid;
  v_lote_id uuid;
  v_tipo public.tipo_preco_pedido;
  v_valor_unitario numeric(10, 2);
  v_quantidade integer;
  v_total_ingressos integer;
begin
  -- Bloqueia a linha do pedido: evita corrida na checagem de quantidade.
  select p.evento_id, p.lote_id, p.tipo_preco, p.valor_unitario, p.quantidade
    into v_evento_id, v_lote_id, v_tipo, v_valor_unitario, v_quantidade
    from public.pedidos p
   where p.id = new.pedido_id
   for update;

  if not found then
    raise exception
      'Ingresso % : pedido % nao encontrado',
      new.id, new.pedido_id
      using errcode = '23503';
  end if;

  -- evento do ingresso deve coincidir com o do pedido
  if new.evento_id <> v_evento_id then
    raise exception
      'Ingresso % : evento % difere do evento % do pedido %',
      new.id, new.evento_id, v_evento_id, new.pedido_id
      using errcode = '23514';
  end if;

  if v_tipo = 'LOTE' then
    if new.lote_id is null or new.lote_id <> v_lote_id then
      raise exception
        'Ingresso % : lote % incompativel com o lote % do pedido %',
        new.id, new.lote_id, v_lote_id, new.pedido_id
        using errcode = '23514';
    end if;
  else
    -- AVULSO
    if new.lote_id is not null then
      raise exception
        'Ingresso % : pedido avulso nao pode ter lote',
        new.id
        using errcode = '23514';
    end if;
  end if;

  -- se houver lote, ele deve ser do mesmo evento do ingresso
  if new.lote_id is not null then
    perform 1
      from public.lotes l
     where l.id = new.lote_id
       and l.evento_id = new.evento_id;

    if not found then
      raise exception
        'Ingresso % : lote % nao pertence ao evento %',
        new.id, new.lote_id, new.evento_id
        using errcode = '23514';
    end if;
  end if;

  -- valor unitario deve bater com o pedido (fonte historica)
  if new.valor_unitario <> v_valor_unitario then
    raise exception
      'Ingresso % : valor_unitario % difere do valor % do pedido %',
      new.id, new.valor_unitario, v_valor_unitario, new.pedido_id
      using errcode = '23514';
  end if;

  -- quantidade de ingressos nao pode exceder a quantidade do pedido
  select count(*)
    into v_total_ingressos
    from public.ingressos i
   where i.pedido_id = new.pedido_id
     and i.id <> new.id;

  if v_total_ingressos + 1 > v_quantidade then
    raise exception
      'Pedido % : limite de % ingressos excedido (ja existem %)',
      new.pedido_id, v_quantidade, v_total_ingressos
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_validar_ingresso_consistencia
  before insert or update on public.ingressos
  for each row execute function public.validar_ingresso_consistencia();

-- PAGAMENTOS ------------------------------------------------------------------
-- Valor do pagamento deve bater com o total do pedido; expira_em, quando
-- informado, deve coincidir com reserva_expira_em do pedido.
create or replace function public.validar_pagamento_consistencia()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_valor_total numeric(10, 2);
  v_reserva_expira_em timestamptz;
begin
  select p.valor_total, p.reserva_expira_em
    into v_valor_total, v_reserva_expira_em
    from public.pedidos p
   where p.id = new.pedido_id;

  if not found then
    raise exception
      'Pagamento % : pedido % nao encontrado',
      new.id, new.pedido_id
      using errcode = '23503';
  end if;

  if new.valor <> v_valor_total then
    raise exception
      'Pagamento % : valor % difere do total % do pedido %',
      new.id, new.valor, v_valor_total, new.pedido_id
      using errcode = '23514';
  end if;

  if new.expira_em is not null and new.expira_em <> v_reserva_expira_em then
    raise exception
      'Pagamento % : expira_em % difere da reserva_expira_em % do pedido %',
      new.id, new.expira_em, v_reserva_expira_em, new.pedido_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_validar_pagamento_consistencia
  before insert or update on public.pagamentos
  for each row execute function public.validar_pagamento_consistencia();

-- ENTRADAS --------------------------------------------------------------------
-- evento da entrada = evento do ingresso; no INSERT, o ingresso nao pode estar
-- EXPIRADO/CANCELADO/RESERVADO. UTILIZADO e permitido (historico/anulacao).
create or replace function public.validar_entrada_consistencia()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_evento_id uuid;
  v_status public.status_ingresso;
begin
  select i.evento_id, i.status
    into v_evento_id, v_status
    from public.ingressos i
   where i.id = new.ingresso_id;

  if not found then
    raise exception
      'Entrada % : ingresso % nao encontrado',
      new.id, new.ingresso_id
      using errcode = '23503';
  end if;

  if new.evento_id <> v_evento_id then
    raise exception
      'Entrada % : evento % difere do evento % do ingresso %',
      new.id, new.evento_id, v_evento_id, new.ingresso_id
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and v_status in ('EXPIRADO', 'CANCELADO', 'RESERVADO') then
    raise exception
      'Entrada % : ingresso % com status % nao pode ser utilizado',
      new.id, new.ingresso_id, v_status
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_validar_entrada_consistencia
  before insert or update on public.entradas
  for each row execute function public.validar_entrada_consistencia();

-- TENTATIVAS DE ENTRADA -------------------------------------------------------
-- Quando ha ingresso, o evento da tentativa deve ser o evento do ingresso.
-- ingresso_id NULL e permitido (ex.: NAO_ENCONTRADO).
create or replace function public.validar_tentativa_entrada_ingresso()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_evento_id uuid;
begin
  if new.ingresso_id is not null then
    select i.evento_id
      into v_evento_id
      from public.ingressos i
     where i.id = new.ingresso_id;

    if not found then
      raise exception
        'Tentativa % : ingresso % nao encontrado',
        new.id, new.ingresso_id
        using errcode = '23503';
    end if;

    if new.evento_id <> v_evento_id then
      raise exception
        'Tentativa % : evento % difere do evento % do ingresso %',
        new.id, new.evento_id, v_evento_id, new.ingresso_id
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_validar_tentativa_entrada_ingresso
  before insert or update on public.tentativas_entrada
  for each row execute function public.validar_tentativa_entrada_ingresso();

-- CANCELAMENTOS / REEMBOLSOS --------------------------------------------------
-- Pagamento (quando informado) deve ser do mesmo pedido; reembolso nao pode
-- exceder o valor pago.
create or replace function public.validar_cancelamento_reembolso()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_pedido_id uuid;
  v_valor_pago numeric(10, 2);
begin
  if new.pagamento_id is not null then
    select p.pedido_id, p.valor
      into v_pedido_id, v_valor_pago
      from public.pagamentos p
     where p.id = new.pagamento_id;

    if not found then
      raise exception
        'Operacao % : pagamento % nao encontrado',
        new.id, new.pagamento_id
        using errcode = '23503';
    end if;

    if v_pedido_id <> new.pedido_id then
      raise exception
        'Operacao % : pagamento % pertence ao pedido %, nao ao pedido %',
        new.id, new.pagamento_id, v_pedido_id, new.pedido_id
        using errcode = '23514';
    end if;

    if new.tipo = 'REEMBOLSO'
       and new.valor is not null
       and new.valor > v_valor_pago then
      raise exception
        'Operacao % : reembolso % excede o valor pago % do pagamento %',
        new.id, new.valor, v_valor_pago, new.pagamento_id
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_validar_cancelamento_reembolso
  before insert or update on public.cancelamentos_reembolsos
  for each row execute function public.validar_cancelamento_reembolso();
