-- =============================================================================
-- Ingressoudi - Eventos de todas as organizacoes (somente super admin)
-- Lista somente leitura com a casa, status, vendas e o lote ativo de cada
-- evento. Valores consideram pedidos PAGO (online e dinheiro).
-- =============================================================================

create or replace function private.listar_eventos_plataforma()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'evento_id',          e.id,
           'nome',               e.nome,
           'slug',               e.slug,
           'imagem_url',         e.imagem_url,
           'inicio_em',          e.inicio_em,
           'local',              e.local,
           'status',             e.status,
           'vendas_status',      e.vendas_status,
           'publicacao_status',  e.publicacao_status,
           'criado_em',          e.criado_em,
           'capacidade_total',   e.capacidade_total,
           'estoque_antecipado', e.estoque_antecipado,
           'meia_entrada_ativa', e.meia_entrada_ativa,
           'organizacao_id',     o.id,
           'organizacao_nome',   o.nome,
           'organizacao_slug',   o.slug,
           'vendidos',           coalesce(ing.vendidos, 0),
           'disponiveis',        private.calcular_disponibilidade_evento(e.id),
           'pedidos_pagos',      coalesce(ped.pedidos, 0),
           'valor_vendido',      coalesce(ped.valor, 0),
           'taxa_plataforma',    coalesce(ped.taxa, 0),
           'lote_atual',         lt.lote
         ) order by e.inicio_em desc, e.nome), '[]'::jsonb)
    into v_res
    from public.eventos e
    join public.organizacoes o on o.id = e.organizacao_id
    left join lateral (
      select count(*) as vendidos
        from public.ingressos i
       where i.evento_id = e.id and i.status in ('VALIDO', 'UTILIZADO')
    ) ing on true
    left join lateral (
      select count(*) as pedidos,
             sum(p.valor_total) as valor,
             sum(p.valor_taxa_total) as taxa
        from public.pedidos p
       where p.evento_id = e.id and p.status = 'PAGO'
    ) ped on true
    left join lateral (
      select jsonb_build_object('nome', l.nome, 'preco', l.preco) as lote
        from public.lotes l
       where l.evento_id = e.id and l.status = 'ATIVO'
       order by l.ordem
       limit 1
    ) lt on true;

  return v_res;
end;
$$;

create or replace function public.listar_eventos_plataforma()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.listar_eventos_plataforma(); $$;

revoke all on function private.listar_eventos_plataforma() from public, anon;
revoke all on function public.listar_eventos_plataforma() from public, anon;
grant execute on function private.listar_eventos_plataforma() to authenticated, service_role;
grant execute on function public.listar_eventos_plataforma() to authenticated, service_role;
