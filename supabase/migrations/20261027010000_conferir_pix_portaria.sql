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

-- Conferencia unica do evento ao abrir a portaria ----------------------------------
-- Quando um operador abre o evento na portaria, o backend confere de uma vez
-- todos os Pix ainda nao aprovados do evento. No maximo uma vez a cada 30
-- minutos por evento (varios aparelhos abrindo a portaria nao repetem).
alter table public.eventos add column if not exists pix_conferido_em timestamptz;

create or replace function private.iniciar_conferencia_pix_evento(p_evento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lista jsonb;
begin
  if auth.uid() is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  update public.eventos e
     set pix_conferido_em = now()
   where e.id = p_evento_id
     and e.organizacao_id = (select private.organizacao_atual_id())
     and (e.pix_conferido_em is null or e.pix_conferido_em < now() - interval '30 minutes');

  if not found then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'pagamento_id', pg.id,
           'organizacao_id', pg.organizacao_id,
           'cobranca_id', pg.cobranca_id,
           'valor', pg.valor)), '[]'::jsonb)
    into v_lista
    from public.pagamentos pg
    join public.pedidos p on p.id = pg.pedido_id
   where p.evento_id = p_evento_id
     and p.status in ('RESERVADO', 'EXPIRADO')
     and pg.provedor = 'MERCADO_PAGO'
     and pg.status in ('PENDENTE', 'EXPIRADO')
     and pg.cobranca_id is not null;

  return v_lista;
end;
$$;

create or replace function public.iniciar_conferencia_pix_evento(p_evento_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.iniciar_conferencia_pix_evento(p_evento_id);
$$;

revoke all on function private.iniciar_conferencia_pix_evento(uuid) from public, anon;
grant execute on function private.iniciar_conferencia_pix_evento(uuid) to authenticated, service_role;
revoke execute on function public.iniciar_conferencia_pix_evento(uuid) from public, anon;
grant execute on function public.iniciar_conferencia_pix_evento(uuid) to authenticated, service_role;
