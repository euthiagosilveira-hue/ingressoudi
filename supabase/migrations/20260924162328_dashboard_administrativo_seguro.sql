-- =============================================================================
-- GZ1 Ingresso - Dashboard administrativo seguro
-- Migration: dashboard_administrativo_seguro
--
-- Superficie ADMIN somente-leitura via RPC (sem SELECT direto nas tabelas):
--   public.listar_eventos_admin()      -> private (SECURITY DEFINER, admin-only)
--   public.obter_dashboard_evento(uuid)-> private (SECURITY DEFINER, admin-only)
--
-- Toda private valida private.usuario_e_admin() (auth.uid()).
-- Nenhuma policy nova. Tabelas seguem fechadas. REVOKE explicito por funcao.
-- =============================================================================

-- private.listar_eventos_admin -------------------------------------------------
create or replace function private.listar_eventos_admin()
returns table (
  id uuid,
  nome text,
  slug text,
  inicio_em timestamptz,
  encerrado_em timestamptz,
  local text,
  status public.status_evento,
  vendas_status public.status_vendas,
  publicacao_status public.status_publicacao,
  capacidade_total integer,
  estoque_antecipado integer,
  criado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  return query
    select e.id, e.nome, e.slug, e.inicio_em, e.encerrado_em, e.local,
           e.status, e.vendas_status, e.publicacao_status,
           e.capacidade_total, e.estoque_antecipado, e.criado_em
      from public.eventos e
     order by e.inicio_em desc;
end;
$$;

-- private.obter_dashboard_evento ----------------------------------------------
create or replace function private.obter_dashboard_evento(p_evento_id uuid)
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
  v_reservas integer;
  v_reservas_ing integer;
  v_bruto numeric;
  v_reembolsado numeric;
  v_liquido numeric;
  v_pagos integer;
  v_ticket numeric;
  v_disp_evento integer;
  v_lote public.lotes%rowtype;
  v_disp_lote integer;
  v_por_hora jsonb;
  v_pagamentos jsonb;
  v_pedidos jsonb;
  v_entradas jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  -- KPIs ---------------------------------------------------------------
  select count(*) into v_vendidos
    from public.ingressos i
   where i.evento_id = p_evento_id and i.status in ('VALIDO', 'UTILIZADO');

  select count(*) into v_utilizados
    from public.ingressos i
   where i.evento_id = p_evento_id and i.status = 'UTILIZADO';

  select count(*), coalesce(sum(p.quantidade), 0)
    into v_reservas, v_reservas_ing
    from public.pedidos p
   where p.evento_id = p_evento_id
     and p.status = 'RESERVADO'
     and p.reserva_expira_em > now();

  select coalesce(sum(p.valor_total), 0), count(*)
    into v_bruto, v_pagos
    from public.pedidos p
   where p.evento_id = p_evento_id and p.status = 'PAGO';

  select coalesce(sum(pg.valor_reembolsado), 0) into v_reembolsado
    from public.pagamentos pg
    join public.pedidos p on p.id = pg.pedido_id
   where p.evento_id = p_evento_id;

  v_liquido := v_bruto - v_reembolsado;
  v_ticket := case when v_pagos > 0 then round(v_liquido / v_pagos, 2) else 0 end;

  v_disp_evento := private.calcular_disponibilidade_evento(p_evento_id);

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id and l.status = 'ATIVO'
   limit 1;
  if v_lote.id is not null then
    v_disp_lote := private.calcular_disponibilidade_lote(v_lote.id);
  end if;

  -- entradas por hora (somente nao anuladas) ----------------------------
  select coalesce(jsonb_agg(jsonb_build_object('hora', to_char(h.h, 'HH24') || ':00', 'quantidade', h.q) order by h.h), '[]'::jsonb)
    into v_por_hora
    from (
      select date_trunc('hour', en.entrada_em) as h, count(*)::int as q
        from public.entradas en
       where en.evento_id = p_evento_id and en.anulada_em is null
       group by 1
    ) h;

  -- pagamentos por status (todos os status principais, zero quando ausente)
  select jsonb_object_agg(s.status::text, jsonb_build_object('quantidade', coalesce(x.q, 0), 'valor', coalesce(x.v, 0)))
    into v_pagamentos
    from (values ('PENDENTE'), ('APROVADO'), ('REJEITADO'), ('CANCELADO'), ('EXPIRADO'), ('REEMBOLSADO')) as s(status)
    left join (
      select pg.status::text as status, count(*)::int as q, coalesce(sum(pg.valor), 0) as v
        from public.pagamentos pg
        join public.pedidos p on p.id = pg.pedido_id
       where p.evento_id = p_evento_id
       group by pg.status::text
    ) x on x.status = s.status;

  -- pedidos recentes (max 10; sem telefone/email) ------------------------
  select coalesce(jsonb_agg(to_jsonb(t) order by t.criado_em desc), '[]'::jsonb)
    into v_pedidos
    from (
      select p.id, p.codigo, p.comprador_nome, p.quantidade, p.valor_total,
             p.status, p.tipo_preco, p.criado_em, p.pago_em
        from public.pedidos p
       where p.evento_id = p_evento_id
       order by p.criado_em desc
       limit 10
    ) t;

  -- entradas recentes (max 10; sem anuladas) -----------------------------
  select coalesce(jsonb_agg(to_jsonb(t) order by t.entrada_em desc), '[]'::jsonb)
    into v_entradas
    from (
      select en.id as entrada_id, en.entrada_em, en.metodo_validacao,
             en.ingresso_id, i.codigo as codigo_ingresso, i.participante_nome,
             en.usuario_id, u.nome as usuario_nome
        from public.entradas en
        join public.ingressos i on i.id = en.ingresso_id
        left join public.usuarios u on u.id = en.usuario_id
       where en.evento_id = p_evento_id and en.anulada_em is null
       order by en.entrada_em desc
       limit 10
    ) t;

  return jsonb_build_object(
    'evento', jsonb_build_object(
      'id', v_evento.id, 'nome', v_evento.nome, 'slug', v_evento.slug,
      'inicio_em', v_evento.inicio_em, 'encerrado_em', v_evento.encerrado_em,
      'local', v_evento.local, 'endereco', v_evento.endereco,
      'status', v_evento.status, 'vendas_status', v_evento.vendas_status,
      'publicacao_status', v_evento.publicacao_status,
      'capacidade_total', v_evento.capacidade_total,
      'estoque_antecipado', v_evento.estoque_antecipado,
      'disponibilidade_evento', v_disp_evento
    ),
    'metricas', jsonb_build_object(
      'vendidos', v_vendidos, 'utilizados', v_utilizados,
      'reservas_ativas', v_reservas, 'ingressos_reservados_ativos', v_reservas_ing,
      'faturamento_bruto', v_bruto, 'valor_reembolsado', v_reembolsado,
      'faturamento_liquido', v_liquido, 'ticket_medio', v_ticket
    ),
    'lote_atual', case when v_lote.id is null then null else jsonb_build_object(
      'id', v_lote.id, 'nome', v_lote.nome, 'ordem', v_lote.ordem, 'preco', v_lote.preco,
      'status', v_lote.status, 'quantidade', v_lote.quantidade,
      'disponibilidade_lote', v_disp_lote, 'ativado_em', v_lote.ativado_em
    ) end,
    'entradas_por_hora', v_por_hora,
    'pagamentos', coalesce(v_pagamentos, '{}'::jsonb),
    'pedidos_recentes', v_pedidos,
    'entradas_recentes', v_entradas
  );
end;
$$;

-- WRAPPERS PUBLICOS (SECURITY INVOKER) ----------------------------------------
create or replace function public.listar_eventos_admin()
returns table (
  id uuid,
  nome text,
  slug text,
  inicio_em timestamptz,
  encerrado_em timestamptz,
  local text,
  status public.status_evento,
  vendas_status public.status_vendas,
  publicacao_status public.status_publicacao,
  capacidade_total integer,
  estoque_antecipado integer,
  criado_em timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.listar_eventos_admin();
$$;

create or replace function public.obter_dashboard_evento(p_evento_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_dashboard_evento(p_evento_id);
$$;

-- ACL EXPLICITA (REVOKE primeiro; sem depender de defaults) -------------------
revoke all on function private.listar_eventos_admin() from public, anon, authenticated;
revoke all on function private.obter_dashboard_evento(uuid) from public, anon, authenticated;
grant execute on function private.listar_eventos_admin() to authenticated, service_role;
grant execute on function private.obter_dashboard_evento(uuid) to authenticated, service_role;

revoke all on function public.listar_eventos_admin() from public, anon, authenticated, service_role;
revoke all on function public.obter_dashboard_evento(uuid) from public, anon, authenticated, service_role;
grant execute on function public.listar_eventos_admin() to authenticated, service_role;
grant execute on function public.obter_dashboard_evento(uuid) to authenticated, service_role;
