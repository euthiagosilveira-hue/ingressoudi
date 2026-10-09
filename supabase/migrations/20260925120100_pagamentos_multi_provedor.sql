-- =============================================================================
-- GZ1 Ingresso - Pagamentos multi-provedor (2/2): modelo neutro + RPCs
-- Migration: pagamentos_multi_provedor
--
-- Objetivo: remover o acoplamento do dominio interno ao Mercado Pago, mantendo
-- STONE (principal) e MERCADO_PAGO (fallback) como providers suportados.
--
-- Escopo:
--   * colunas neutras transacao_id, cobranca_id, referencia_externa
--   * copia de mercado_pago_payment_id / mercado_pago_external_reference
--   * default do provedor para STONE
--   * criar_pagamento_pendente(pedido, provider, transacao, cobranca, referencia)
--   * confirmar_pagamento(pagamento_id, transacao, referencia)  [idempotente]
--   * unicidade parcial (provedor, transacao_id)
--   * indices neutros
--   * ACLs explicitas
--   * remocao dos campos legados apos copia segura
--
-- Fora do escopo: integracao real Stone/Mercado Pago, webhooks, adapters,
-- mapeamento de status externo, frontend. Sem DROP/DELETE de dados de negocio.
--
-- Idempotente. Requer a migration anterior (enum STONE) ja aplicada.
-- =============================================================================

-- 1) COLUNAS NEUTRAS ----------------------------------------------------------
alter table public.pagamentos add column if not exists transacao_id text null;
alter table public.pagamentos add column if not exists cobranca_id text null;
alter table public.pagamentos add column if not exists referencia_externa text null;

-- 2) MIGRACAO DOS DADOS LEGADOS (somente se as colunas legadas existirem) -----
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pagamentos'
       and column_name = 'mercado_pago_payment_id'
  ) then
    execute $sql$
      update public.pagamentos
         set transacao_id = coalesce(transacao_id, mercado_pago_payment_id)
       where mercado_pago_payment_id is not null
    $sql$;
  end if;

  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pagamentos'
       and column_name = 'mercado_pago_external_reference'
  ) then
    execute $sql$
      update public.pagamentos
         set referencia_externa = coalesce(referencia_externa, mercado_pago_external_reference)
       where mercado_pago_external_reference is not null
    $sql$;
  end if;
end $$;

-- 3) PROVEDOR PADRAO (STONE e o principal; MERCADO_PAGO permanece suportado) --
alter table public.pagamentos alter column provedor set default 'STONE';

-- 4) RPC criar_pagamento_pendente: remover overload legado (1 argumento) ------
drop function if exists public.criar_pagamento_pendente(uuid);
drop function if exists private.criar_pagamento_pendente(uuid);

create or replace function private.criar_pagamento_pendente(
  p_pedido_id uuid,
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
  v_pagamento_id uuid;
begin
  if p_provider is null then
    raise exception 'provider obrigatorio' using errcode = '23514';
  end if;

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

  insert into public.pagamentos (
    pedido_id, provedor, valor, expira_em,
    transacao_id, cobranca_id, referencia_externa
  ) values (
    p_pedido_id, p_provider, v_pedido.valor_total, v_pedido.reserva_expira_em,
    p_transaction_id, p_charge_id, p_referencia_externa
  )
  returning id into v_pagamento_id;

  return jsonb_build_object(
    'pagamento_id', v_pagamento_id,
    'pedido_id', p_pedido_id,
    'provedor', p_provider,
    'valor', v_pedido.valor_total,
    'status', 'PENDENTE',
    'expira_em', v_pedido.reserva_expira_em,
    'transacao_id', p_transaction_id,
    'cobranca_id', p_charge_id,
    'referencia_externa', p_referencia_externa
  );
end;
$$;

-- 5) RPC confirmar_pagamento: agora por pagamento_id (adapter resolve o externo)
--    DROP necessario: CREATE OR REPLACE nao permite renomear parametros (42P13).
--    A ACL e reaplicada na secao 11.
drop function if exists public.confirmar_pagamento(uuid, text, text);
drop function if exists private.confirmar_pagamento(uuid, text, text);

create or replace function private.confirmar_pagamento(
  p_pagamento_id uuid,
  p_transaction_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pagamento public.pagamentos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_ingressos integer := 0;
begin
  select * into v_pagamento
    from public.pagamentos pg
   where pg.id = p_pagamento_id
   for update;

  if not found then
    raise exception 'Pagamento % nao encontrado', p_pagamento_id using errcode = '23503';
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.id = v_pagamento.pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', v_pagamento.pedido_id using errcode = '23503';
  end if;

  -- idempotencia: confirmar duas vezes nao duplica efeitos
  if v_pedido.status = 'PAGO' and v_pagamento.status = 'APROVADO' then
    return jsonb_build_object(
      'pedido_id', v_pedido.id,
      'pagamento_id', v_pagamento.id,
      'status', 'PAGO',
      'resultado', 'ja_confirmado'
    );
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', v_pedido.id, v_pedido.status
      using errcode = '23514';
  end if;

  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido % expirada', v_pedido.id using errcode = '23514';
  end if;

  if v_pagamento.status <> 'PENDENTE' then
    raise exception 'Pagamento % nao esta PENDENTE (status=%)', v_pagamento.id, v_pagamento.status
      using errcode = '23514';
  end if;

  if v_pagamento.valor <> v_pedido.valor_total then
    raise exception 'Pagamento % valor % difere do total % do pedido',
      v_pagamento.id, v_pagamento.valor, v_pedido.valor_total using errcode = '23514';
  end if;

  update public.pagamentos
     set status = 'APROVADO',
         confirmado_em = now(),
         transacao_id = coalesce(p_transaction_id, transacao_id),
         referencia_externa = coalesce(p_referencia_externa, referencia_externa)
   where id = v_pagamento.id;

  update public.pedidos
     set status = 'PAGO', pago_em = now()
   where id = v_pedido.id;

  update public.ingressos
     set status = 'VALIDO'
   where pedido_id = v_pedido.id and status = 'RESERVADO';
  get diagnostics v_ingressos = row_count;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'pagamento_id', v_pagamento.id,
    'status', 'PAGO',
    'ingressos_validados', v_ingressos,
    'resultado', 'confirmado'
  );
end;
$$;

-- 6) WRAPPERS PUBLICOS (SECURITY INVOKER) -------------------------------------
create or replace function public.criar_pagamento_pendente(
  p_pedido_id uuid,
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
  select private.criar_pagamento_pendente(
    p_pedido_id, p_provider, p_transaction_id, p_charge_id, p_referencia_externa
  );
$$;

create or replace function public.confirmar_pagamento(
  p_pagamento_id uuid,
  p_transaction_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.confirmar_pagamento(p_pagamento_id, p_transaction_id, p_referencia_externa);
$$;

-- 7) UNICIDADE NEUTRA: (provedor, transacao_id) parcial -----------------------
alter table public.pagamentos drop constraint if exists uq_pagamentos_mp_payment_id;

create unique index if not exists uq_pagamentos_provedor_transacao
  on public.pagamentos (provedor, transacao_id)
  where transacao_id is not null;

-- 8) INDICES NEUTROS ----------------------------------------------------------
create index if not exists idx_pagamentos_provedor
  on public.pagamentos (provedor);

create index if not exists idx_pagamentos_referencia_externa
  on public.pagamentos (referencia_externa);

-- 9) REMOVER COLUNAS LEGADAS (apos copia e sem dependencias) ------------------
-- Indices/constraints que as referenciam sao removidos automaticamente.
alter table public.pagamentos drop column if exists mercado_pago_payment_id;
alter table public.pagamentos drop column if exists mercado_pago_external_reference;

-- 10) CANCELAMENTOS/REEMBOLSOS: neutralizar identificador de reembolso --------
-- Alvo: reembolso_externo_id (neutro, padrao portugues do schema).
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'cancelamentos_reembolsos'
       and column_name = 'mercado_pago_refund_id'
  ) then
    alter table public.cancelamentos_reembolsos
      rename column mercado_pago_refund_id to reembolso_externo_id;
  end if;
end $$;

-- 11) ACL ---------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;

-- compra publica (checkout): anon, authenticated, service_role
revoke all on function private.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text) from public;
grant execute on function private.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)
  to anon, authenticated, service_role;

revoke execute on function public.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.criar_pagamento_pendente(uuid, public.provedor_pagamento, text, text, text)
  to anon, authenticated, service_role;

-- confirmacao de pagamento (system/provider callback): somente service_role
revoke all on function private.confirmar_pagamento(uuid, text, text) from public;
grant execute on function private.confirmar_pagamento(uuid, text, text) to service_role;

revoke execute on function public.confirmar_pagamento(uuid, text, text) from public, anon, authenticated;
grant execute on function public.confirmar_pagamento(uuid, text, text) to service_role;

-- 12) DOCUMENTACAO DE NEUTRALIDADE --------------------------------------------
comment on column public.pagamentos.transacao_id is
  'Identificador da transacao no provedor (neutro). Stone/Mercado Pago.';
comment on column public.pagamentos.cobranca_id is
  'Identificador da cobranca no provedor (neutro, opcional).';
comment on column public.pagamentos.referencia_externa is
  'Correlacao GZ1 <-> provedor externo (neutra).';
