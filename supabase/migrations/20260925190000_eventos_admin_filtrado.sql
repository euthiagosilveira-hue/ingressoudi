-- =============================================================================
-- GZ1 Ingresso - Listagem administrativa de eventos (filtros + contagens)
-- Migration: eventos_admin_filtrado
--
-- Superficie ADMIN somente-leitura via RPC (sem SELECT direto nas tabelas):
--   public.listar_eventos_admin_filtrado(busca, status, publicacao, vendas)
--     -> private (SECURITY DEFINER, admin-only)
--
-- Ordenacao: EM_ANDAMENTO, depois AGENDADO (inicio asc), depois REALIZADO/
-- CANCELADO (inicio desc). Busca em nome/slug/local (case-insensitive).
-- Nao expoe dados financeiros. Nao altera RLS/ACL existentes.
-- =============================================================================

create or replace function private.listar_eventos_admin_filtrado(
  p_busca text default null,
  p_status public.status_evento default null,
  p_publicacao public.status_publicacao default null,
  p_vendas public.status_vendas default null
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
               'evento_id', e.id,
               'nome', e.nome,
               'slug', e.slug,
               'inicio_em', e.inicio_em,
               'local', e.local,
               'status', e.status,
               'vendas_status', e.vendas_status,
               'publicacao_status', e.publicacao_status,
               'capacidade_total', e.capacidade_total,
               'estoque_antecipado', e.estoque_antecipado,
               'publicado_em', e.publicado_em,
               'lotes_count', (select count(*) from public.lotes l where l.evento_id = e.id),
               'pedidos_count', (select count(*) from public.pedidos p where p.evento_id = e.id),
               'ingressos_count', (select count(*) from public.ingressos i where i.evento_id = e.id)
             )
             order by
               case e.status when 'EM_ANDAMENTO' then 0 when 'AGENDADO' then 1 else 2 end,
               case when e.status in ('REALIZADO', 'CANCELADO') then e.inicio_em end desc nulls last,
               e.inicio_em asc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.eventos e
   where (
       p_busca is null or btrim(p_busca) = ''
       or e.nome ilike '%' || p_busca || '%'
       or e.slug ilike '%' || p_busca || '%'
       or e.local ilike '%' || p_busca || '%'
     )
     and (p_status is null or e.status = p_status)
     and (p_publicacao is null or e.publicacao_status = p_publicacao)
     and (p_vendas is null or e.vendas_status = p_vendas);

  return v_itens;
end;
$$;

create or replace function public.listar_eventos_admin_filtrado(
  p_busca text default null,
  p_status public.status_evento default null,
  p_publicacao public.status_publicacao default null,
  p_vendas public.status_vendas default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.listar_eventos_admin_filtrado(p_busca, p_status, p_publicacao, p_vendas);
$$;

-- ACL (admin-only via check interno; anon sem EXECUTE) ------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.listar_eventos_admin_filtrado(
  text, public.status_evento, public.status_publicacao, public.status_vendas
) from public;
grant execute on function private.listar_eventos_admin_filtrado(
  text, public.status_evento, public.status_publicacao, public.status_vendas
) to authenticated, service_role;

revoke execute on function public.listar_eventos_admin_filtrado(
  text, public.status_evento, public.status_publicacao, public.status_vendas
) from public, anon, authenticated, service_role;
grant execute on function public.listar_eventos_admin_filtrado(
  text, public.status_evento, public.status_publicacao, public.status_vendas
) to authenticated, service_role;

comment on function public.listar_eventos_admin_filtrado(
  text, public.status_evento, public.status_publicacao, public.status_vendas
) is 'Listagem administrativa de eventos (ADMINISTRADOR). Filtros opcionais + contagens.';
