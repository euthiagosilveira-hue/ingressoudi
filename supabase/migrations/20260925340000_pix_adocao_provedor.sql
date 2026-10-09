-- =============================================================================
-- GZ1 Ingresso - Pix: adocao de provedor em pagamento PENDENTE legado
-- Migration: pix_adocao_provedor
--
-- Reaplica private.criar_pagamento_pendente_por_token permitindo que um
-- pagamento PENDENTE ja existente e SEM cobranca externa (ex.: criado
-- historicamente como STONE) seja adotado pelo provedor solicitado
-- (MERCADO_PAGO). Pagamentos com cobranca externa continuam protegidos
-- (erro controlado), evitando troca indevida de provedor.
-- =============================================================================

create or replace function private.criar_pagamento_pendente_por_token(
  p_token uuid,
  p_provider public.provedor_pagamento,
  p_transaction_id text default null,
  p_charge_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language plpgsql
volatile
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
    if v_pag.provedor <> p_provider then
      -- Adota o provedor somente se ainda nao houver cobranca externa real.
      if v_pag.status = 'PENDENTE' and v_pag.cobranca_id is null then
        update public.pagamentos set provedor = p_provider where id = v_pag.id;
        v_pag.provedor := p_provider;
      else
        raise exception 'Pedido ja possui pagamento iniciado com outro provedor' using errcode = '23514';
      end if;
    end if;

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
