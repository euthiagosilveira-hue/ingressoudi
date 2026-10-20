-- =============================================================================
-- Ingressoudi - Dashboard de um evento (botao "Ver dashboard" do evento)
-- obter_painel_evento_admin(p_evento_id): mesmo formato do obter_dashboard_admin
-- (metricas, evento, entradasPorHora, pagamentosPorStatus, pedidosRecentes,
-- entradasRecentes), mas restrito a um evento da organizacao ativa, com as
-- mesmas regras de calculo, para os numeros baterem com o Dashboard geral.
-- Entradas por hora: horas reais do evento, no horario de Sao Paulo.
-- Extra: lote atual, reservas abertas e valor reembolsado.
-- =============================================================================

create or replace function private.obter_painel_evento_admin(p_evento_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_vendidos integer;
  v_utilizados integer;
  v_faturamento numeric;
  v_reembolsado numeric;
  v_reservas integer;
  v_lote public.lotes%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO')),
         count(*) filter (where i.status = 'UTILIZADO')
    into v_vendidos, v_utilizados
    from public.ingressos i
   where i.evento_id = p_evento_id;

  select coalesce(sum(pg.valor) filter (where pg.status = 'APROVADO'), 0),
         coalesce(sum(pg.valor_reembolsado), 0)
    into v_faturamento, v_reembolsado
    from public.pagamentos pg
    join public.pedidos p on p.id = pg.pedido_id
   where p.evento_id = p_evento_id;

  select count(*) into v_reservas
    from public.pedidos p
   where p.evento_id = p_evento_id and p.status = 'RESERVADO' and p.reserva_expira_em > now();

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id and l.status = 'ATIVO'
   limit 1;

  return jsonb_build_object(
    'metricas', jsonb_build_object(
      'vendidos', v_vendidos,
      'utilizados', v_utilizados,
      'naoEntraram', greatest(v_vendidos - v_utilizados, 0),
      'faturamento', v_faturamento,
      'ticketMedio', case when v_vendidos > 0 then round(v_faturamento / v_vendidos, 2) else 0 end
    ),
    'evento', jsonb_build_object(
      'evento_id', v_evento.id, 'nome', v_evento.nome, 'slug', v_evento.slug,
      'imagem_url', v_evento.imagem_url, 'inicio_em', v_evento.inicio_em,
      'local', v_evento.local, 'status', v_evento.status
    ),
    'entradasPorHora', (
      select coalesce(jsonb_agg(jsonb_build_object('hora', to_char(h.h, 'HH24') || 'h', 'entradas', h.q) order by h.h), '[]'::jsonb)
        from (
          select date_trunc('hour', en.entrada_em at time zone 'America/Sao_Paulo') as h, count(*)::int as q
            from public.entradas en
           where en.evento_id = p_evento_id and en.anulada_em is null
           group by 1
        ) h
    ),
    'pagamentosPorStatus', (
      select jsonb_build_array(
        jsonb_build_object('key', 'paid', 'label', 'Pago',
          'value', count(*) filter (where pg.status = 'APROVADO')),
        jsonb_build_object('key', 'pending', 'label', 'Pendente',
          'value', count(*) filter (where pg.status = 'PENDENTE')),
        jsonb_build_object('key', 'canceled', 'label', 'Cancelado',
          'value', count(*) filter (where pg.status in ('REJEITADO', 'CANCELADO', 'EXPIRADO', 'REEMBOLSADO'))))
        from public.pagamentos pg
        join public.pedidos p on p.id = pg.pedido_id
       where p.evento_id = p_evento_id
    ),
    'pedidosRecentes', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.criado_em desc), '[]'::jsonb)
        from (
          select p.id as pedido_id, p.codigo, p.comprador_nome as buyer,
                 p.quantidade as tickets, p.valor_total as total, p.status, p.criado_em,
                 (select count(*) from public.ingressos i where i.pedido_id = p.id and i.status = 'UTILIZADO') as entrance_used
            from public.pedidos p
           where p.evento_id = p_evento_id
           order by p.criado_em desc
           limit 10
        ) t
    ),
    'entradasRecentes', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.entrada_em desc), '[]'::jsonb)
        from (
          select en.id, i.participante_nome as name, i.codigo, en.entrada_em, en.metodo_validacao
            from public.entradas en
            join public.ingressos i on i.id = en.ingresso_id
           where en.evento_id = p_evento_id and en.anulada_em is null
           order by en.entrada_em desc
           limit 10
        ) t
    ),
    'extras', jsonb_build_object(
      'reservasAtivas', v_reservas,
      'valorReembolsado', v_reembolsado,
      'vendasStatus', v_evento.vendas_status,
      'capacidadeTotal', v_evento.capacidade_total,
      'loteAtual', case when v_lote.id is null then null else jsonb_build_object(
        'nome', v_lote.nome, 'preco', v_lote.preco,
        'disponiveis', private.calcular_disponibilidade_lote(v_lote.id)) end
    )
  );
end;
$$;

create or replace function public.obter_painel_evento_admin(p_evento_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_painel_evento_admin(p_evento_id); $$;

revoke all on function private.obter_painel_evento_admin(uuid) from public, anon;
grant execute on function private.obter_painel_evento_admin(uuid) to authenticated, service_role;
revoke all on function public.obter_painel_evento_admin(uuid) from public, anon;
grant execute on function public.obter_painel_evento_admin(uuid) to authenticated, service_role;
