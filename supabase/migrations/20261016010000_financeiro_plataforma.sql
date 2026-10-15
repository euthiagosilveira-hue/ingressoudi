-- =============================================================================
-- Ingressoudi - Financeiro da plataforma (somente super admin)
-- Resumo por periodo (datas no fuso America/Sao_Paulo, pelo pago_em do pedido):
--  * online (Mercado Pago): valor cobrado do comprador, taxa da plataforma
--    (application_fee = pedidos.valor_taxa_total) e valor do produtor antes da
--    tarifa do Mercado Pago;
--  * dinheiro (venda manual): sem taxa.
-- Considera somente pedidos PAGO com pagamento APROVADO.
-- =============================================================================

create or replace function private.financeiro_plataforma(p_inicio date, p_fim date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_de timestamptz;
  v_ate timestamptz;
  v_res jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  if p_fim - p_inicio > 366 then
    raise exception 'Periodo invalido: maximo de 1 ano' using errcode = '22023';
  end if;

  v_de := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_ate := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';

  with vendas as (
    select p.organizacao_id,
           (pg.provedor = 'MERCADO_PAGO') as online,
           p.quantidade,
           p.valor_total,
           p.valor_taxa_total,
           (p.pago_em at time zone 'America/Sao_Paulo')::date as dia
      from public.pedidos p
      join lateral (
        select g.provedor from public.pagamentos g
         where g.pedido_id = p.id and g.status = 'APROVADO'
         order by g.confirmado_em desc nulls last
         limit 1
      ) pg on true
     where p.status = 'PAGO'
       and p.pago_em >= v_de and p.pago_em < v_ate
  ),
  por_org as (
    select v.organizacao_id,
           count(*) filter (where v.online)                              as pedidos_online,
           coalesce(sum(v.quantidade) filter (where v.online), 0)        as ingressos_online,
           coalesce(sum(v.valor_total) filter (where v.online), 0)       as bruto_online,
           coalesce(sum(v.valor_taxa_total) filter (where v.online), 0)  as taxa_plataforma,
           count(*) filter (where not v.online)                          as pedidos_dinheiro,
           coalesce(sum(v.quantidade) filter (where not v.online), 0)    as ingressos_dinheiro,
           coalesce(sum(v.valor_total) filter (where not v.online), 0)   as bruto_dinheiro
      from vendas v
     group by v.organizacao_id
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('inicio', p_inicio, 'fim', p_fim),
    'totais', jsonb_build_object(
      'pedidos_online',     coalesce(sum(o.pedidos_online), 0),
      'ingressos_online',   coalesce(sum(o.ingressos_online), 0),
      'bruto_online',       coalesce(sum(o.bruto_online), 0),
      'taxa_plataforma',    coalesce(sum(o.taxa_plataforma), 0),
      'repasse_produtores', coalesce(sum(o.bruto_online - o.taxa_plataforma), 0),
      'pedidos_dinheiro',   coalesce(sum(o.pedidos_dinheiro), 0),
      'ingressos_dinheiro', coalesce(sum(o.ingressos_dinheiro), 0),
      'bruto_dinheiro',     coalesce(sum(o.bruto_dinheiro), 0),
      'casas_com_vendas',   count(*)
    ),
    'organizacoes', coalesce(jsonb_agg(jsonb_build_object(
      'organizacao_id',     org.id,
      'nome',               org.nome,
      'slug',               org.slug,
      'pedidos_online',     o.pedidos_online,
      'ingressos_online',   o.ingressos_online,
      'bruto_online',       o.bruto_online,
      'taxa_plataforma',    o.taxa_plataforma,
      'repasse_produtor',   o.bruto_online - o.taxa_plataforma,
      'pedidos_dinheiro',   o.pedidos_dinheiro,
      'ingressos_dinheiro', o.ingressos_dinheiro,
      'bruto_dinheiro',     o.bruto_dinheiro
    ) order by o.taxa_plataforma desc, o.bruto_online desc, org.nome), '[]'::jsonb),
    'por_dia', coalesce((
      select jsonb_agg(jsonb_build_object('dia', d.dia, 'taxa_plataforma', d.taxa, 'bruto_online', d.bruto) order by d.dia)
        from (select v.dia,
                     coalesce(sum(v.valor_taxa_total) filter (where v.online), 0) as taxa,
                     coalesce(sum(v.valor_total) filter (where v.online), 0) as bruto
                from vendas v group by v.dia) d
    ), '[]'::jsonb)
  )
  into v_res
  from por_org o
  join public.organizacoes org on org.id = o.organizacao_id;

  return v_res;
end;
$$;

create or replace function public.financeiro_plataforma(p_inicio date, p_fim date)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.financeiro_plataforma(p_inicio, p_fim); $$;

revoke all on function private.financeiro_plataforma(date, date) from public, anon;
revoke all on function public.financeiro_plataforma(date, date) from public, anon;
grant execute on function private.financeiro_plataforma(date, date) to authenticated, service_role;
grant execute on function public.financeiro_plataforma(date, date) to authenticated, service_role;
