-- =============================================================================
-- GZ1 Ingresso - Dashboard administrativo (somente leitura)
-- Migration: dashboard_admin
--
-- RPC ADMIN-only que agrega metricas, evento atual/proximo, entradas por hora,
-- pagamentos por status, pedidos recentes e entradas recentes.
-- Nao expoe tokens/secrets. Nao altera RLS/ACL.
-- =============================================================================

create or replace function public.obter_dashboard_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_vendidos integer;
  v_utilizados integer;
  v_faturamento numeric;
  v_evento jsonb;
  v_res jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO')),
         count(*) filter (where i.status = 'UTILIZADO')
    into v_vendidos, v_utilizados
    from public.ingressos i;

  select coalesce(sum(pg.valor), 0) into v_faturamento
    from public.pagamentos pg where pg.status = 'APROVADO';

  -- Evento atual (EM_ANDAMENTO) ou proximo AGENDADO
  select to_jsonb(t) into v_evento
    from (
      select e.id, e.nome, e.slug, e.inicio_em, e.local, e.status
        from public.eventos e
       where e.status = 'EM_ANDAMENTO'
       order by e.inicio_em desc
       limit 1
    ) t;

  if v_evento is null then
    select to_jsonb(t) into v_evento
      from (
        select e.id, e.nome, e.slug, e.inicio_em, e.local, e.status
          from public.eventos e
         where e.status = 'AGENDADO' and e.inicio_em >= now()
         order by e.inicio_em asc
         limit 1
      ) t;
  end if;

  select jsonb_build_object(
    'metricas', jsonb_build_object(
      'vendidos', v_vendidos,
      'utilizados', v_utilizados,
      'naoEntraram', greatest(v_vendidos - v_utilizados, 0),
      'faturamento', v_faturamento,
      'ticketMedio', case when v_vendidos > 0 then round(v_faturamento / v_vendidos, 2) else 0 end
    ),
    'evento', v_evento,
    'entradasPorHora', (
      select coalesce(jsonb_agg(jsonb_build_object('hora', l.hora, 'entradas', coalesce(c.q, 0)) order by l.ord), '[]'::jsonb)
        from (values ('18h',0,'18'),('19h',1,'19'),('20h',2,'20'),('21h',3,'21'),('22h',4,'22'),
                     ('23h',5,'23'),('00h',6,'00'),('01h',7,'01'),('02h',8,'02'),('03h',9,'03'),('04h',10,'04'))
             as l(hora, ord, hh)
        left join (
          select to_char(en.entrada_em at time zone 'America/Sao_Paulo', 'HH24') as hh, count(*) as q
            from public.entradas en
           where en.anulada_em is null
             and en.entrada_em >= (
               (date_trunc('day', now() at time zone 'America/Sao_Paulo')
                 - case when extract(hour from (now() at time zone 'America/Sao_Paulo')) < 6 then interval '1 day' else interval '0' end)
               + interval '18 hours'
             ) at time zone 'America/Sao_Paulo'
             and en.entrada_em < (
               (date_trunc('day', now() at time zone 'America/Sao_Paulo')
                 - case when extract(hour from (now() at time zone 'America/Sao_Paulo')) < 6 then interval '1 day' else interval '0' end)
               + interval '29 hours'
             ) at time zone 'America/Sao_Paulo'
           group by 1
        ) c on c.hh = l.hh
    ),
    'pagamentosPorStatus', jsonb_build_array(
      jsonb_build_object('key', 'paid', 'label', 'Pago',
        'value', (select count(*) from public.pagamentos where status = 'APROVADO')),
      jsonb_build_object('key', 'pending', 'label', 'Pendente',
        'value', (select count(*) from public.pagamentos where status = 'PENDENTE')),
      jsonb_build_object('key', 'canceled', 'label', 'Cancelado',
        'value', (select count(*) from public.pagamentos where status in ('REJEITADO','CANCELADO','EXPIRADO','REEMBOLSADO')))
    ),
    'pedidosRecentes', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.criado_em desc), '[]'::jsonb)
        from (
          select p.id as pedido_id, p.codigo, p.comprador_nome as buyer,
                 p.quantidade as tickets, p.valor_total as total, p.status, p.criado_em,
                 (select count(*) from public.ingressos i where i.pedido_id = p.id and i.status = 'UTILIZADO') as entrance_used
            from public.pedidos p
           order by p.criado_em desc
           limit 5
        ) t
    ),
    'entradasRecentes', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.entrada_em desc), '[]'::jsonb)
        from (
          select en.id, i.participante_nome as name, i.codigo, en.entrada_em, en.metodo_validacao
            from public.entradas en
            join public.ingressos i on i.id = en.ingresso_id
           where en.anulada_em is null
           order by en.entrada_em desc
           limit 5
        ) t
    )
  ) into v_res;

  return v_res;
end;
$$;

revoke execute on function public.obter_dashboard_admin() from public, anon, authenticated, service_role;
grant execute on function public.obter_dashboard_admin() to authenticated, service_role;

comment on function public.obter_dashboard_admin() is
  'KPIs e listas recentes do dashboard (ADMINISTRADOR). Sem tokens/secrets.';
