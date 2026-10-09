-- =============================================================================
-- GZ1 Ingresso - Financeiro administrativo (somente leitura)
-- Migration: financeiro_admin
--
-- RPC ADMIN-only que retorna resumo + movimentacoes de pagamentos reais.
-- Faturamento confirmado = SUM(pagamentos.valor) WHERE status = 'APROVADO'.
-- Nao expoe pix copia-e-cola, pix qr, checkout_token, qr_token ou secrets.
-- Nao altera RLS/ACL.
-- =============================================================================

create or replace function public.obter_financeiro_admin(
  p_evento_id uuid default null,
  p_busca text default null,
  p_de timestamptz default null,
  p_ate timestamptz default null,
  p_status_pagamento public.status_pagamento default null,
  p_provedor public.provedor_pagamento default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  create temporary table _fin_base on commit drop as
  select
    pg.id, pg.pedido_id, pg.provedor, pg.status, pg.valor, pg.valor_reembolsado,
    pg.transacao_id, pg.cobranca_id, pg.referencia_externa, pg.expira_em,
    pg.confirmado_em, pg.cancelado_em, pg.reembolsado_em, pg.criado_em,
    p.codigo as pedido_codigo, p.comprador_nome, p.evento_id, e.nome as evento_nome
  from public.pagamentos pg
  join public.pedidos p on p.id = pg.pedido_id
  join public.eventos e on e.id = p.evento_id
  where (p_evento_id is null or p.evento_id = p_evento_id)
    and (p_de is null or coalesce(pg.confirmado_em, pg.criado_em) >= p_de)
    and (p_ate is null or coalesce(pg.confirmado_em, pg.criado_em) <= p_ate)
    and (p_status_pagamento is null or pg.status = p_status_pagamento)
    and (p_provedor is null or pg.provedor = p_provedor)
    and (
      p_busca is null or btrim(p_busca) = ''
      or p.codigo ilike '%' || p_busca || '%'
      or p.comprador_nome ilike '%' || p_busca || '%'
      or pg.transacao_id ilike '%' || p_busca || '%'
      or pg.referencia_externa ilike '%' || p_busca || '%'
    );

  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'total', (select count(*) from _fin_base),
      'aprovados', (select count(*) from _fin_base where status = 'APROVADO'),
      'valorAprovado', (select coalesce(sum(valor), 0) from _fin_base where status = 'APROVADO'),
      'pendente', (select coalesce(sum(valor), 0) from _fin_base where status = 'PENDENTE'),
      'reembolsado', (select coalesce(sum(valor_reembolsado), 0) from _fin_base),
      'liquido', (
        (select coalesce(sum(valor), 0) from _fin_base where status = 'APROVADO')
        - (select coalesce(sum(valor_reembolsado), 0) from _fin_base)
      )
    ),
    'movimentacoes', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'pagamento_id', b.id,
            'pedido_id', b.pedido_id,
            'pedido_codigo', b.pedido_codigo,
            'evento_id', b.evento_id,
            'evento_nome', b.evento_nome,
            'comprador_nome', b.comprador_nome,
            'provedor', b.provedor,
            'status', b.status,
            'valor', b.valor,
            'valor_reembolsado', b.valor_reembolsado,
            'transacao_id', b.transacao_id,
            'cobranca_id', b.cobranca_id,
            'referencia_externa', b.referencia_externa,
            'expira_em', b.expira_em,
            'confirmado_em', b.confirmado_em,
            'cancelado_em', b.cancelado_em,
            'reembolsado_em', b.reembolsado_em,
            'criado_em', b.criado_em
          )
          order by coalesce(b.confirmado_em, b.criado_em) desc
        ),
        '[]'::jsonb
      )
      from _fin_base b
    )
  ) into v_res;

  return v_res;
end;
$$;

revoke execute on function public.obter_financeiro_admin(
  uuid, text, timestamptz, timestamptz, public.status_pagamento, public.provedor_pagamento
) from public, anon, authenticated, service_role;
grant execute on function public.obter_financeiro_admin(
  uuid, text, timestamptz, timestamptz, public.status_pagamento, public.provedor_pagamento
) to authenticated, service_role;

comment on function public.obter_financeiro_admin(
  uuid, text, timestamptz, timestamptz, public.status_pagamento, public.provedor_pagamento
) is 'Resumo financeiro + movimentacoes (ADMINISTRADOR). Sem dados sensiveis.';
