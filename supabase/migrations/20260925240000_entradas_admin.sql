-- =============================================================================
-- GZ1 Ingresso - Entradas administrativas (somente leitura)
-- Migration: entradas_admin
--
-- RPC ADMIN-only que lista ENTRADAS EFETIVAMENTE REGISTRADAS (public.entradas),
-- com filtros opcionais. NAO lista tentativas recusadas (tentativas_entrada).
-- Nao expoe qr_token/checkout_token/recovery/share. Nao altera RLS/ACL.
-- =============================================================================

create or replace function public.listar_entradas_admin(
  p_evento_id uuid default null,
  p_busca text default null,
  p_de timestamptz default null,
  p_ate timestamptz default null,
  p_metodo public.metodo_validacao default null,
  p_situacao text default null
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
               'entrada_id', en.id,
               'entrada_em', en.entrada_em,
               'metodo', en.metodo_validacao,
               'anulada_em', en.anulada_em,
               'anulada_por_nome', ua.nome,
               'motivo_anulacao', en.motivo_anulacao,
               'ingresso_id', i.id,
               'ingresso_codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'ingresso_status', i.status,
               'pedido_id', p.id,
               'pedido_codigo', p.codigo,
               'evento_id', en.evento_id,
               'evento_nome', e.nome,
               'evento_inicio_em', e.inicio_em,
               'operador_id', en.usuario_id,
               'operador_nome', u.nome,
               'criado_em', en.criado_em
             )
             order by en.entrada_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.entradas en
    join public.ingressos i on i.id = en.ingresso_id
    join public.pedidos p on p.id = i.pedido_id
    join public.eventos e on e.id = en.evento_id
    left join public.usuarios u on u.id = en.usuario_id
    left join public.usuarios ua on ua.id = en.anulada_por_usuario_id
   where (p_evento_id is null or en.evento_id = p_evento_id)
     and (p_de is null or en.entrada_em >= p_de)
     and (p_ate is null or en.entrada_em <= p_ate)
     and (p_metodo is null or en.metodo_validacao = p_metodo)
     and (
       p_situacao is null
       or (p_situacao = 'ATIVA' and en.anulada_em is null)
       or (p_situacao = 'ANULADA' and en.anulada_em is not null)
     )
     and (
       p_busca is null or btrim(p_busca) = ''
       or i.codigo ilike '%' || p_busca || '%'
       or i.participante_nome ilike '%' || p_busca || '%'
       or p.codigo ilike '%' || p_busca || '%'
       or u.nome ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$$;

revoke execute on function public.listar_entradas_admin(
  uuid, text, timestamptz, timestamptz, public.metodo_validacao, text
) from public, anon, authenticated, service_role;
grant execute on function public.listar_entradas_admin(
  uuid, text, timestamptz, timestamptz, public.metodo_validacao, text
) to authenticated, service_role;

comment on function public.listar_entradas_admin(
  uuid, text, timestamptz, timestamptz, public.metodo_validacao, text
) is 'Listagem administrativa de entradas efetivadas (ADMINISTRADOR). Sem tokens.';
