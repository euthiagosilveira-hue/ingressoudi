-- =============================================================================
-- Ingressoudi - Numero de "disponiveis" e "vendidos" nos cards de Eventos
-- O card da lista de eventos do painel mostrava sempre "0 disponiveis" (o valor
-- nao vinha do banco) e contava como vendidos tambem ingressos expirados ou
-- cancelados. listar_eventos_admin_filtrado passa a devolver:
--   * ingressos_vendidos: ingressos VALIDO + UTILIZADO;
--   * disponiveis: private.calcular_disponibilidade_evento (estoque do evento
--     menos vendidos e reservas ativas), nunca negativo.
-- Corpo identico ao de 20261020060000_listar_eventos_meia_entrada.sql, mais os
-- dois campos. Pode rodar mais de uma vez.
-- =============================================================================

CREATE OR REPLACE FUNCTION private.listar_eventos_admin_filtrado(p_busca text DEFAULT NULL::text, p_status status_evento DEFAULT NULL::status_evento, p_publicacao status_publicacao DEFAULT NULL::status_publicacao, p_vendas status_vendas DEFAULT NULL::status_vendas)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
               'imagem_url', e.imagem_url,
               'meia_entrada_ativa', e.meia_entrada_ativa,
               'lote_ativo_id', la.id,
               'lote_ativo_nome', la.nome,
               'lote_ativo_ordem', la.ordem,
               'lote_ativo_preco', la.preco,
               'lote_ativo_quantidade', la.quantidade,
               'lote_ativo_vendidos', (
                 select count(*) from public.ingressos i
                  where i.lote_id = la.id and i.status in ('VALIDO', 'UTILIZADO')
               ),
               'lote_ativo_disponiveis', private.calcular_disponibilidade_lote(la.id),
               'lotes_count', (select count(*) from public.lotes l where l.evento_id = e.id),
               'pedidos_count', (select count(*) from public.pedidos p where p.evento_id = e.id),
               'ingressos_count', (select count(*) from public.ingressos i where i.evento_id = e.id),
               -- Ingressos efetivamente vendidos (pagos ou ja usados na portaria).
               'ingressos_vendidos', (
                 select count(*) from public.ingressos i
                  where i.evento_id = e.id and i.status in ('VALIDO', 'UTILIZADO')
               ),
               -- Quanto ainda pode ser vendido: estoque do evento menos vendidos e
               -- reservas de Pix ainda dentro do prazo (mesma regra do checkout).
               'disponiveis', greatest(coalesce(private.calcular_disponibilidade_evento(e.id), 0), 0)
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
    left join lateral (
      select l.id, l.nome, l.ordem, l.preco, l.quantidade
        from public.lotes l
       where l.evento_id = e.id and l.status = 'ATIVO'
       order by l.ordem asc
       limit 1
    ) la on true
   where e.organizacao_id = (select private.organizacao_atual_id())
     and (
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
$function$;

-- Registro da migracao (quem roda este arquivo direto no SQL Editor) ----------
do $$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    insert into supabase_migrations.schema_migrations (version, name)
    values ('20261109010000', 'eventos_disponiveis_card')
    on conflict (version) do nothing;
  end if;
end;
$$;
