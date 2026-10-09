-- =============================================================================
-- GZ1 Ingresso - Ingressos do checkout (pos-pagamento)
-- Migration: ingressos_checkout_seguro
--
-- Objetivo: permitir que o comprador acesse os ingressos do proprio pedido a
-- partir do checkout_token (bearer), SEM abrir SELECT em ingressos/pedidos e
-- SEM expor qr_token antes do pagamento aprovado.
--
-- Escopo:
--   * private.obter_ingressos_checkout(token)  (SECURITY DEFINER)
--   * public.obter_ingressos_checkout(token)   (SECURITY INVOKER)
--   * devolve ingressos apenas se pedido PAGO e pagamento APROVADO
--   * qr_token somente para ingresso VALIDO/UTILIZADO
--     (CANCELADO retorna estado informativo, sem QR utilizavel;
--      RESERVADO/EXPIRADO nao sao retornados)
--
-- NAO altera RLS/policies, NAO abre SELECT direto, NAO altera o fluxo de
-- portaria nem o formato/geracao do qr_token.
-- Padrao: public SECURITY INVOKER -> private SECURITY DEFINER, search_path=''.
-- =============================================================================

-- 1) RPC privada -------------------------------------------------------------
create or replace function private.obter_ingressos_checkout(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  if p_token is null then
    return null;
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = v_pedido.evento_id;

  v_disponivel := v_pedido.status = 'PAGO'
    and exists (
      select 1
        from public.pagamentos pg
       where pg.pedido_id = v_pedido.id
         and pg.status = 'APROVADO'
    );

  if v_disponivel then
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 -- QR utilizavel somente para ingresso apto a entrar.
                 'qr_token',
                   case
                     when i.status in ('VALIDO', 'UTILIZADO') then i.qr_token
                     else null
                   end,
                 'utilizado_em', i.utilizado_em
               ) order by i.codigo
             ),
             '[]'::jsonb
           )
      into v_ingressos
      from public.ingressos i
     where i.pedido_id = v_pedido.id
       and i.status in ('VALIDO', 'UTILIZADO', 'CANCELADO');
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$$;

-- 2) Wrapper publico ---------------------------------------------------------
create or replace function public.obter_ingressos_checkout(p_token uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_ingressos_checkout(p_token);
$$;

-- 3) ACL ---------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;

-- privada: chamada pelo wrapper (SECURITY INVOKER) em nome de anon/auth
revoke all on function private.obter_ingressos_checkout(uuid) from public;
grant execute on function private.obter_ingressos_checkout(uuid)
  to anon, authenticated, service_role;

-- publica: posse do checkout_token e a autorizacao
revoke execute on function public.obter_ingressos_checkout(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.obter_ingressos_checkout(uuid)
  to anon, authenticated, service_role;

comment on function public.obter_ingressos_checkout(uuid) is
  'Ingressos do pedido via checkout_token. So retorna com pedido PAGO e '
  'pagamento APROVADO. qr_token apenas para ingresso VALIDO/UTILIZADO.';
