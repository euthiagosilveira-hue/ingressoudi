-- =============================================================================
-- GZ1 Ingresso - Backend de pagamento (Mercado Pago) - RPCs service_role-only
-- Migration: checkout_pagamento_backend
--
-- Cria operacoes internas usadas SOMENTE pelo backend (service_role):
--   * private/public.obter_checkout_pagamento_backend(p_token uuid)
--       -> dados minimos do checkout, incluindo comprador_email (nunca exposto
--          ao navegador via obter_checkout_pedido).
--   * private/public.registrar_cobranca_externa(...)
--       -> persiste IDs/QR do provider no pagamento interno, idempotente.
--
-- ACL: somente service_role. Nao expor a anon/authenticated.
-- Nao altera RLS, nao cria colunas, nao abre UPDATE direto.
-- =============================================================================

-- 1) OBTER CHECKOUT (backend) -------------------------------------------------
create or replace function private.obter_checkout_pagamento_backend(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
begin
  select * into v_pedido from public.pedidos p where p.checkout_token = p_token limit 1;
  if not found then
    return null;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'comprador_email', v_pedido.comprador_email,
    'valor_total', v_pedido.valor_total,
    'pedido_status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pagamento_id', v_pag.id,
    'provedor', v_pag.provedor,
    'pagamento_status', v_pag.status,
    'transacao_id', v_pag.transacao_id,
    'cobranca_id', v_pag.cobranca_id,
    'referencia_externa', v_pag.referencia_externa,
    'pix_copia_cola', v_pag.pix_copia_cola,
    'pix_qr_code', v_pag.pix_qr_code,
    'expira_em', v_pag.expira_em
  );
end;
$$;

create or replace function public.obter_checkout_pagamento_backend(p_token uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_checkout_pagamento_backend(p_token);
$$;

-- 2) REGISTRAR COBRANCA EXTERNA (backend) -------------------------------------
create or replace function private.registrar_cobranca_externa(
  p_pagamento_id uuid,
  p_provider public.provedor_pagamento,
  p_transacao_id text default null,
  p_cobranca_id text default null,
  p_referencia_externa text default null,
  p_pix_copia_cola text default null,
  p_pix_qr_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pag public.pagamentos%rowtype;
begin
  select * into v_pag from public.pagamentos pg where pg.id = p_pagamento_id for update;
  if not found then
    raise exception 'Pagamento % nao encontrado', p_pagamento_id using errcode = '23503';
  end if;

  if v_pag.provedor <> p_provider then
    raise exception 'Pagamento % pertence a outro provider (%)', p_pagamento_id, v_pag.provedor
      using errcode = '23514';
  end if;

  if v_pag.status not in ('PENDENTE') then
    raise exception 'Pagamento % nao esta PENDENTE (status=%)', p_pagamento_id, v_pag.status
      using errcode = '23514';
  end if;

  -- conflito: cobranca externa ja registrada com id diferente
  if v_pag.cobranca_id is not null and v_pag.cobranca_id <> p_cobranca_id then
    raise exception 'Pagamento % ja possui cobranca externa %', p_pagamento_id, v_pag.cobranca_id
      using errcode = '23505';
  end if;

  update public.pagamentos
     set transacao_id = coalesce(transacao_id, p_transacao_id),
         cobranca_id = coalesce(cobranca_id, p_cobranca_id),
         referencia_externa = coalesce(referencia_externa, p_referencia_externa),
         pix_copia_cola = coalesce(pix_copia_cola, p_pix_copia_cola),
         pix_qr_code = coalesce(pix_qr_code, p_pix_qr_code)
   where id = p_pagamento_id;

  return jsonb_build_object(
    'pagamento_id', p_pagamento_id,
    'cobranca_id', coalesce(v_pag.cobranca_id, p_cobranca_id),
    'transacao_id', coalesce(v_pag.transacao_id, p_transacao_id),
    'reutilizado', v_pag.cobranca_id is not null
  );
end;
$$;

create or replace function public.registrar_cobranca_externa(
  p_pagamento_id uuid,
  p_provider public.provedor_pagamento,
  p_transacao_id text default null,
  p_cobranca_id text default null,
  p_referencia_externa text default null,
  p_pix_copia_cola text default null,
  p_pix_qr_code text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.registrar_cobranca_externa(
    p_pagamento_id, p_provider, p_transacao_id, p_cobranca_id,
    p_referencia_externa, p_pix_copia_cola, p_pix_qr_code
  );
$$;

-- 3) ACL: somente service_role ------------------------------------------------
revoke execute on function public.obter_checkout_pagamento_backend(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.obter_checkout_pagamento_backend(uuid) to service_role;
revoke all on function private.obter_checkout_pagamento_backend(uuid) from public, anon, authenticated;
grant execute on function private.obter_checkout_pagamento_backend(uuid) to service_role;

revoke execute on function public.registrar_cobranca_externa(
  uuid, public.provedor_pagamento, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.registrar_cobranca_externa(
  uuid, public.provedor_pagamento, text, text, text, text, text
) to service_role;
revoke all on function private.registrar_cobranca_externa(
  uuid, public.provedor_pagamento, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function private.registrar_cobranca_externa(
  uuid, public.provedor_pagamento, text, text, text, text, text
) to service_role;
