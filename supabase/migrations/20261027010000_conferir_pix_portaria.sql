-- =============================================================================
-- Ingressoudi - Portaria confere o Pix de ingresso expirado ou nao pago
--
-- Se o aviso (webhook) do Mercado Pago nao chegar e o comprador fechar a pagina
-- de pagamento, o pedido pago fica RESERVADO e depois EXPIRADO, e a portaria
-- barra quem pagou. Esta funcao diz ao backend qual Pix conferir no Mercado
-- Pago quando a portaria le um ingresso EXPIRADO ou RESERVADO. A confirmacao em
-- si continua sendo private.confirmar_pagamento (service_role), que ja aceita
-- pedido EXPIRADO e audita a confirmacao tardia.
-- =============================================================================

create or replace function private.localizar_pix_portaria(p_evento_id uuid, p_ingresso_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pix record;
begin
  if auth.uid() is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  select pg.id, pg.organizacao_id, pg.cobranca_id, pg.valor
    into v_pix
    from public.ingressos i
    join public.pagamentos pg on pg.pedido_id = i.pedido_id
   where i.id = p_ingresso_id
     and i.evento_id = p_evento_id
     and i.organizacao_id = (select private.organizacao_atual_id())
     and i.status in ('EXPIRADO', 'RESERVADO')
     and pg.provedor = 'MERCADO_PAGO'
     and pg.status in ('PENDENTE', 'EXPIRADO')
     and pg.cobranca_id is not null
   order by pg.criado_em desc
   limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'pagamento_id', v_pix.id,
    'organizacao_id', v_pix.organizacao_id,
    'cobranca_id', v_pix.cobranca_id,
    'valor', v_pix.valor
  );
end;
$$;

create or replace function public.localizar_pix_portaria(p_evento_id uuid, p_ingresso_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.localizar_pix_portaria(p_evento_id, p_ingresso_id);
$$;

revoke all on function private.localizar_pix_portaria(uuid, uuid) from public, anon;
grant execute on function private.localizar_pix_portaria(uuid, uuid) to authenticated, service_role;
revoke execute on function public.localizar_pix_portaria(uuid, uuid) from public, anon;
grant execute on function public.localizar_pix_portaria(uuid, uuid) to authenticated, service_role;
