-- =============================================================================
-- GZ1 Ingresso - Ingressos administrativos (listagem + detalhe)
-- Migration: ingressos_admin
--
-- Superficie ADMIN somente-leitura via RPC (sem SELECT direto nas tabelas):
--   public.listar_ingressos_admin(evento, pedido, busca, status)
--   public.obter_ingresso_admin(p_ingresso_id)
--     -> private (SECURITY DEFINER, admin-only)
--
-- NAO expoe qr_token, checkout_token ou secrets.
-- Nao altera RLS/ACL existentes.
-- =============================================================================

create or replace function public.listar_ingressos_admin(
  p_evento_id uuid default null,
  p_pedido_id uuid default null,
  p_busca text default null,
  p_status public.status_ingresso default null
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
               'ingresso_id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'status', i.status,
               'valor_unitario', i.valor_unitario,
               'utilizado_em', i.utilizado_em,
               'criado_em', i.criado_em,
               'pedido_id', i.pedido_id,
               'pedido_codigo', p.codigo,
               'evento_id', i.evento_id,
               'evento_nome', e.nome,
               'evento_inicio_em', e.inicio_em,
               'lote_id', i.lote_id,
               'lote_nome', l.nome
             )
             order by i.criado_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.ingressos i
    join public.pedidos p on p.id = i.pedido_id
    join public.eventos e on e.id = i.evento_id
    left join public.lotes l on l.id = i.lote_id
   where (p_evento_id is null or i.evento_id = p_evento_id)
     and (p_pedido_id is null or i.pedido_id = p_pedido_id)
     and (p_status is null or i.status = p_status)
     and (
       p_busca is null or btrim(p_busca) = ''
       or i.codigo ilike '%' || p_busca || '%'
       or i.participante_nome ilike '%' || p_busca || '%'
       or p.codigo ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$$;

create or replace function public.obter_ingresso_admin(p_ingresso_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ing public.ingressos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_entrada public.entradas%rowtype;
  v_entrada_json jsonb := null;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_ing from public.ingressos i where i.id = p_ingresso_id;
  if not found then
    return null;
  end if;

  select * into v_pedido from public.pedidos p where p.id = v_ing.pedido_id;
  select * into v_evento from public.eventos e where e.id = v_ing.evento_id;
  if v_ing.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_ing.lote_id;
  end if;

  select * into v_entrada
    from public.entradas en
   where en.ingresso_id = v_ing.id and en.anulada_em is null
   order by en.entrada_em desc
   limit 1;
  if found then
    v_entrada_json := jsonb_build_object(
      'entrada_id', v_entrada.id,
      'entrada_em', v_entrada.entrada_em,
      'metodo', v_entrada.metodo_validacao
    );
  end if;

  return jsonb_build_object(
    'ingresso_id', v_ing.id,
    'codigo', v_ing.codigo,
    'participante_nome', v_ing.participante_nome,
    'status', v_ing.status,
    'valor_unitario', v_ing.valor_unitario,
    'utilizado_em', v_ing.utilizado_em,
    'criado_em', v_ing.criado_em,
    'pedido_id', v_ing.pedido_id,
    'pedido_codigo', v_pedido.codigo,
    'pedido_status', v_pedido.status,
    'evento_id', v_ing.evento_id,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'lote_id', v_ing.lote_id,
    'lote_nome', v_lote.nome,
    'entrada', v_entrada_json
  );
end;
$$;

-- ACL (admin-only via check interno) ------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke execute on function public.listar_ingressos_admin(
  uuid, uuid, text, public.status_ingresso
) from public, anon, authenticated, service_role;
grant execute on function public.listar_ingressos_admin(
  uuid, uuid, text, public.status_ingresso
) to authenticated, service_role;

revoke execute on function public.obter_ingresso_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function public.obter_ingresso_admin(uuid) to authenticated, service_role;

comment on function public.listar_ingressos_admin(uuid, uuid, text, public.status_ingresso) is
  'Listagem administrativa de ingressos (ADMINISTRADOR). Sem qr_token.';
comment on function public.obter_ingresso_admin(uuid) is
  'Detalhe administrativo de ingresso (ADMINISTRADOR). Sem qr_token.';
