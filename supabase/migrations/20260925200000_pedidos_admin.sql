-- =============================================================================
-- GZ1 Ingresso - Pedidos administrativos (listagem + detalhe)
-- Migration: pedidos_admin
--
-- Superficie ADMIN somente-leitura via RPC (sem SELECT direto nas tabelas):
--   public.listar_pedidos_admin(evento, busca, status, pagamento, tipo, de, ate)
--   public.obter_pedido_admin(pedido_id)
--     -> private (SECURITY DEFINER, admin-only)
--
-- Nao expoe qr_token, checkout_token, pix copia-e-cola ou secrets.
-- Nao altera RLS/ACL existentes.
-- =============================================================================

create or replace function public.listar_pedidos_admin(
  p_evento_id uuid default null,
  p_busca text default null,
  p_status public.status_pedido default null,
  p_pagamento_status public.status_pagamento default null,
  p_tipo_preco public.tipo_preco_pedido default null,
  p_de timestamptz default null,
  p_ate timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', p.id,
               'codigo', p.codigo,
               'evento_id', p.evento_id,
               'evento_nome', e.nome,
               'lote_id', p.lote_id,
               'lote_nome', l.nome,
               'comprador_nome', p.comprador_nome,
               'comprador_telefone', p.comprador_telefone,
               'comprador_email', p.comprador_email,
               'quantidade', p.quantidade,
               'tipo_preco', p.tipo_preco,
               'valor_unitario', p.valor_unitario,
               'valor_total', p.valor_total,
               'status', p.status,
               'reserva_expira_em', p.reserva_expira_em,
               'pago_em', p.pago_em,
               'cancelado_em', p.cancelado_em,
               'criado_em', p.criado_em,
               'atualizado_em', p.atualizado_em,
               'motivo_valor_avulso', p.motivo_valor_avulso,
               'autorizado_por_nome', u.nome,
               'pagamento_status', pg.status,
               'pagamento_valor', pg.valor
             )
             order by p.criado_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.pedidos p
    join public.eventos e on e.id = p.evento_id
    left join public.lotes l on l.id = p.lote_id
    left join public.usuarios u on u.id = p.autorizado_por_usuario_id
    left join public.pagamentos pg on pg.pedido_id = p.id
   where (p_evento_id is null or p.evento_id = p_evento_id)
     and (
       p_busca is null or btrim(p_busca) = ''
       or p.codigo ilike '%' || p_busca || '%'
       or p.comprador_nome ilike '%' || p_busca || '%'
       or p.comprador_telefone ilike '%' || p_busca || '%'
       or p.comprador_email ilike '%' || p_busca || '%'
     )
     and (p_status is null or p.status = p_status)
     and (p_pagamento_status is null or pg.status = p_pagamento_status)
     and (p_tipo_preco is null or p.tipo_preco = p_tipo_preco)
     and (p_de is null or p.criado_em >= p_de)
     and (p_ate is null or p.criado_em <= p_ate);

  return v_itens;
end;
$$;

create or replace function public.obter_pedido_admin(p_pedido_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pag_json jsonb;
  v_autorizado text;
  v_ingressos jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_pedido from public.pedidos p where p.id = p_pedido_id;
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;
  if v_pedido.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_pedido.lote_id;
  end if;
  if v_pedido.autorizado_por_usuario_id is not null then
    select nome into v_autorizado from public.usuarios u where u.id = v_pedido.autorizado_por_usuario_id;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;
  if found then
    v_pag_json := jsonb_build_object(
      'id', v_pag.id,
      'status', v_pag.status,
      'valor', v_pag.valor,
      'provedor', v_pag.provedor,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa,
      'expira_em', v_pag.expira_em,
      'confirmado_em', v_pag.confirmado_em,
      'cancelado_em', v_pag.cancelado_em,
      'reembolsado_em', v_pag.reembolsado_em,
      'valor_reembolsado', v_pag.valor_reembolsado
    );
  else
    v_pag_json := null;
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'valor_unitario', i.valor_unitario,
               'status', i.status,
               'utilizado_em', i.utilizado_em
             ) order by i.codigo
           ),
           '[]'::jsonb
         )
    into v_ingressos
    from public.ingressos i
   where i.pedido_id = v_pedido.id;

  return jsonb_build_object(
    'id', v_pedido.id,
    'codigo', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'comprador_nome', v_pedido.comprador_nome,
    'comprador_telefone', v_pedido.comprador_telefone,
    'comprador_email', v_pedido.comprador_email,
    'quantidade', v_pedido.quantidade,
    'tipo_preco', v_pedido.tipo_preco,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_total', v_pedido.valor_total,
    'status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pago_em', v_pedido.pago_em,
    'cancelado_em', v_pedido.cancelado_em,
    'criado_em', v_pedido.criado_em,
    'atualizado_em', v_pedido.atualizado_em,
    'motivo_valor_avulso', v_pedido.motivo_valor_avulso,
    'autorizado_por_nome', v_autorizado,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'pagamento', v_pag_json,
    'ingressos', v_ingressos
  );
end;
$$;

-- ACL (admin-only via check interno) ------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke execute on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) to authenticated, service_role;

revoke execute on function public.obter_pedido_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function public.obter_pedido_admin(uuid) to authenticated, service_role;

comment on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) is 'Listagem administrativa de pedidos (ADMINISTRADOR). Sem qr_token/checkout_token.';
comment on function public.obter_pedido_admin(uuid) is
  'Detalhe administrativo de pedido (ADMINISTRADOR). Sem qr_token.';
