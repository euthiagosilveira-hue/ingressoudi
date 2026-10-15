-- =============================================================================
-- Ingressoudi - Reembolso de pedidos pelo produtor
-- Fluxo (executado pelo servidor, com service_role, apos conferir que o usuario
-- e ADMINISTRADOR da organizacao ativa):
--   1) preparar_reembolso_pedido: valida e registra a operacao PENDENTE
--      (idempotente: se ja houver operacao pendente para o pedido, devolve a mesma);
--   2) servidor estorna no Mercado Pago (X-Idempotency-Key = id da operacao);
--      venda em dinheiro nao chama o Mercado Pago (devolucao feita pelo produtor);
--   3) concluir_reembolso_pedido: sucesso -> pagamento REEMBOLSADO, pedido
--      CANCELADO, ingressos CANCELADO; falha -> operacao FALHOU (pedido intacto).
-- Regras: so pedido PAGO, sem ingresso ja utilizado na portaria. Reembolso total
-- (ingressos + taxa de servico), conforme a politica de reembolso.
-- =============================================================================

create or replace function private.preparar_reembolso_pedido(
  p_pedido_id uuid,
  p_organizacao_id uuid,
  p_usuario_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
  v_op public.cancelamentos_reembolsos%rowtype;
begin
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'Informe o motivo do reembolso' using errcode = '23514';
  end if;

  select * into v_pedido from public.pedidos p
   where p.id = p_pedido_id and p.organizacao_id = p_organizacao_id
   for update;
  if not found then
    raise exception 'Pedido nao encontrado' using errcode = '23503';
  end if;

  -- operacao pendente anterior (ex.: falha de rede no meio): reaproveita
  select * into v_op from public.cancelamentos_reembolsos c
   where c.pedido_id = v_pedido.id and c.tipo = 'REEMBOLSO' and c.status = 'PENDENTE'
   order by c.solicitado_em desc limit 1;

  if v_pedido.status <> 'PAGO' then
    raise exception 'Somente pedido pago pode ser reembolsado' using errcode = '23514';
  end if;
  if exists (select 1 from public.ingressos i where i.pedido_id = v_pedido.id and i.status = 'UTILIZADO') then
    raise exception 'Pedido com ingresso ja utilizado na portaria nao pode ser reembolsado' using errcode = '23514';
  end if;

  select * into v_pag from public.pagamentos pg
   where pg.pedido_id = v_pedido.id and pg.status = 'APROVADO'
   order by pg.confirmado_em desc nulls last limit 1;
  if not found then
    raise exception 'Pagamento aprovado nao encontrado para o pedido' using errcode = '23503';
  end if;

  if v_op.id is null then
    insert into public.cancelamentos_reembolsos
      (pedido_id, pagamento_id, tipo, status, valor, motivo, usuario_id, organizacao_id)
    values
      (v_pedido.id, v_pag.id, 'REEMBOLSO', 'PENDENTE', v_pag.valor, btrim(p_motivo), p_usuario_id, p_organizacao_id)
    returning * into v_op;

    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
    values (p_usuario_id, 'REEMBOLSO_SOLICITADO', 'pedidos', v_pedido.id,
            jsonb_build_object('operacao_id', v_op.id, 'valor', v_pag.valor, 'motivo', btrim(p_motivo)),
            p_organizacao_id);
  end if;

  return jsonb_build_object(
    'operacao_id', v_op.id,
    'pedido_id', v_pedido.id,
    'pagamento_id', v_pag.id,
    'provedor', v_pag.provedor,
    'transacao_id', coalesce(v_pag.transacao_id, v_pag.cobranca_id),
    'valor', v_pag.valor
  );
end;
$$;

create or replace function private.concluir_reembolso_pedido(
  p_operacao_id uuid,
  p_organizacao_id uuid,
  p_sucesso boolean,
  p_reembolso_externo_id text default null,
  p_observacao text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_op public.cancelamentos_reembolsos%rowtype;
  v_ts timestamptz := now();
  v_ingressos integer := 0;
begin
  select * into v_op from public.cancelamentos_reembolsos c
   where c.id = p_operacao_id and c.organizacao_id = p_organizacao_id
   for update;
  if not found then
    raise exception 'Operacao de reembolso nao encontrada' using errcode = '23503';
  end if;
  if v_op.status <> 'PENDENTE' then
    return jsonb_build_object('operacao_id', v_op.id, 'status', v_op.status, 'ja_processada', true);
  end if;

  if not coalesce(p_sucesso, false) then
    update public.cancelamentos_reembolsos
       set status = 'FALHOU', processado_em = v_ts, observacao = left(coalesce(p_observacao, ''), 500)
     where id = v_op.id;
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
    values (v_op.usuario_id, 'REEMBOLSO_FALHOU', 'pedidos', v_op.pedido_id,
            jsonb_build_object('operacao_id', v_op.id, 'observacao', left(coalesce(p_observacao, ''), 500)),
            v_op.organizacao_id);
    return jsonb_build_object('operacao_id', v_op.id, 'status', 'FALHOU');
  end if;

  update public.pagamentos
     set status = 'REEMBOLSADO', valor_reembolsado = valor, reembolsado_em = v_ts
   where id = v_op.pagamento_id;

  update public.pedidos
     set status = 'CANCELADO', cancelado_em = v_ts
   where id = v_op.pedido_id;

  update public.ingressos
     set status = 'CANCELADO'
   where pedido_id = v_op.pedido_id and status in ('VALIDO', 'RESERVADO');
  get diagnostics v_ingressos = row_count;

  update public.cancelamentos_reembolsos
     set status = 'CONCLUIDO', processado_em = v_ts,
         reembolso_externo_id = nullif(btrim(coalesce(p_reembolso_externo_id, '')), ''),
         observacao = nullif(left(coalesce(p_observacao, ''), 500), '')
   where id = v_op.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (v_op.usuario_id, 'REEMBOLSO_CONCLUIDO', 'pedidos', v_op.pedido_id,
          jsonb_build_object('operacao_id', v_op.id, 'valor', v_op.valor,
                             'reembolso_externo_id', p_reembolso_externo_id, 'ingressos_cancelados', v_ingressos),
          v_op.organizacao_id);

  return jsonb_build_object('operacao_id', v_op.id, 'status', 'CONCLUIDO',
                            'valor', v_op.valor, 'ingressos_cancelados', v_ingressos);
end;
$$;

-- wrappers no public somente para o servidor (service_role); nunca anon/authenticated
create or replace function public.preparar_reembolso_pedido(
  p_pedido_id uuid, p_organizacao_id uuid, p_usuario_id uuid, p_motivo text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.preparar_reembolso_pedido(p_pedido_id, p_organizacao_id, p_usuario_id, p_motivo); $$;

create or replace function public.concluir_reembolso_pedido(
  p_operacao_id uuid, p_organizacao_id uuid, p_sucesso boolean,
  p_reembolso_externo_id text default null, p_observacao text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.concluir_reembolso_pedido(p_operacao_id, p_organizacao_id, p_sucesso, p_reembolso_externo_id, p_observacao); $$;

revoke all on function private.preparar_reembolso_pedido(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.concluir_reembolso_pedido(uuid, uuid, boolean, text, text) from public, anon, authenticated;
revoke all on function public.preparar_reembolso_pedido(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.concluir_reembolso_pedido(uuid, uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function private.preparar_reembolso_pedido(uuid, uuid, uuid, text) to service_role;
grant execute on function private.concluir_reembolso_pedido(uuid, uuid, boolean, text, text) to service_role;
grant execute on function public.preparar_reembolso_pedido(uuid, uuid, uuid, text) to service_role;
grant execute on function public.concluir_reembolso_pedido(uuid, uuid, boolean, text, text) to service_role;

-- Rota publica nova (/reembolso): reservar o endereco para nenhuma casa usar.
do $$
begin
  if exists (select 1 from public.organizacoes where lower(slug) in ('reembolso', 'ajuda')) then
    raise exception 'Existe organizacao com slug reembolso/ajuda: renomeie antes de aplicar';
  end if;
end $$;

create or replace function private.slug_organizacao_reservado(p_slug text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_slug, '')) = any (array['admin', 'ajuda', 'api', 'app', 'auth', 'cadastro', 'configuracoes', 'contato', 'dashboard-teste', 'entradas', 'eventos', 'eventos-publicos', 'financeiro', 'ingresso', 'ingressos', 'lista-vip', 'login', 'meus-ingressos', 'painel', 'pedidos', 'plataforma', 'portaria', 'privacidade', 'recuperar-ingressos', 'reembolso', 'sobre', 'suporte', 'termos', 'www', '_nuxt']::text[]);
$$;
