-- =============================================================================
-- Ingressoudi - Reserva cobre o Pix e lote nao fecha por reserva nao paga
-- Migration: reserva_pix_e_lotes
--
-- 1) private.estender_reserva_pix: o Pix do Mercado Pago vale no minimo 30
--    minutos a partir de quando e gerado, um pouco depois da reserva (30 min a
--    partir do pedido). O backend estende a reserva ate o fim do Pix, para o
--    comprador nunca pagar um Pix cuja reserva ja venceu.
-- 2) private.confirmar_pagamento: se mesmo assim chegar a aprovacao de um Pix
--    com reserva vencida (pedido RESERVADO vencido ou EXPIRADO), os ingressos
--    sao emitidos. O comprador pagou; a confirmacao e auditada, inclusive
--    quando passa do estoque antecipado.
-- 3) private.processar_virada_lote_esgotamento: sem proximo lote, o lote ativo
--    so e encerrado quando os ingressos PAGOS atingem a quantidade. Lote cheio
--    so de reservas fica ativo e volta a vender quando elas vencem.
-- 4) private.ativar_lote_manual: lote ENCERRADO pode ser reativado se ainda
--    tiver ingressos disponiveis.
-- =============================================================================

-- 1) Estende a reserva ate o fim do Pix ------------------------------------------
create or replace function private.estender_reserva_pix(
  p_pagamento_id uuid,
  p_expira_em timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pagamento public.pagamentos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_alvo timestamptz;
begin
  if p_expira_em is null then
    raise exception 'Prazo do Pix ausente' using errcode = '22004';
  end if;

  select * into v_pagamento from public.pagamentos pg where pg.id = p_pagamento_id for update;
  if not found then
    raise exception 'Pagamento % nao encontrado', p_pagamento_id using errcode = '23503';
  end if;

  select * into v_pedido from public.pedidos p where p.id = v_pagamento.pedido_id for update;
  if not found then
    raise exception 'Pedido % nao encontrado', v_pagamento.pedido_id using errcode = '23503';
  end if;

  if v_pedido.status <> 'RESERVADO' or v_pagamento.status <> 'PENDENTE' then
    return jsonb_build_object('resultado', 'nao_aplicavel', 'reserva_expira_em', v_pedido.reserva_expira_em);
  end if;

  -- reserva ja vencida nao e ressuscitada (o estoque pode ter sido revendido)
  if now() >= v_pedido.reserva_expira_em then
    return jsonb_build_object('resultado', 'reserva_expirada', 'reserva_expira_em', v_pedido.reserva_expira_em);
  end if;

  -- trava de seguranca: nunca alem de 90 minutos a partir de agora
  v_alvo := least(p_expira_em, now() + interval '90 minutes');

  if v_alvo <= v_pedido.reserva_expira_em then
    return jsonb_build_object('resultado', 'mantida', 'reserva_expira_em', v_pedido.reserva_expira_em);
  end if;

  -- pedido primeiro: o gatilho de pagamentos exige expira_em = reserva_expira_em
  update public.pedidos set reserva_expira_em = v_alvo where id = v_pedido.id;
  update public.pagamentos set expira_em = v_alvo where id = v_pagamento.id;

  return jsonb_build_object(
    'resultado', 'estendida',
    'reserva_expira_em', v_alvo,
    'reserva_anterior', v_pedido.reserva_expira_em
  );
end;
$$;

create or replace function public.estender_reserva_pix(
  p_pagamento_id uuid,
  p_expira_em timestamptz
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.estender_reserva_pix(p_pagamento_id, p_expira_em);
$$;

revoke all on function private.estender_reserva_pix(uuid, timestamptz) from public, anon, authenticated;
grant execute on function private.estender_reserva_pix(uuid, timestamptz) to service_role;
revoke execute on function public.estender_reserva_pix(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.estender_reserva_pix(uuid, timestamptz) to service_role;

-- 2) Confirmacao aceita Pix pago depois da reserva -------------------------------
create or replace function private.confirmar_pagamento(
  p_pagamento_id uuid,
  p_transaction_id text default null,
  p_referencia_externa text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pagamento public.pagamentos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_ingressos integer := 0;
  v_tardio boolean := false;
  v_disp integer;
  v_qtd integer;
begin
  select * into v_pagamento
    from public.pagamentos pg
   where pg.id = p_pagamento_id
   for update;

  if not found then
    raise exception 'Pagamento % nao encontrado', p_pagamento_id using errcode = '23503';
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.id = v_pagamento.pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', v_pagamento.pedido_id using errcode = '23503';
  end if;

  -- idempotencia: confirmar duas vezes nao duplica efeitos
  if v_pedido.status = 'PAGO' and v_pagamento.status = 'APROVADO' then
    return jsonb_build_object(
      'pedido_id', v_pedido.id,
      'pagamento_id', v_pagamento.id,
      'status', 'PAGO',
      'resultado', 'ja_confirmado'
    );
  end if;

  if v_pedido.status not in ('RESERVADO', 'EXPIRADO') then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', v_pedido.id, v_pedido.status
      using errcode = '23514';
  end if;

  if v_pagamento.status not in ('PENDENTE', 'EXPIRADO') then
    raise exception 'Pagamento % nao esta PENDENTE (status=%)', v_pagamento.id, v_pagamento.status
      using errcode = '23514';
  end if;

  if v_pagamento.valor <> v_pedido.valor_total then
    raise exception 'Pagamento % valor % difere do total % do pedido',
      v_pagamento.id, v_pagamento.valor, v_pedido.valor_total using errcode = '23514';
  end if;

  -- Pix aprovado depois de a reserva vencer: o comprador pagou, entao os
  -- ingressos sao emitidos. O evento e bloqueado como em criar_reserva, para
  -- medir o estoque sem corrida, e o caso fica na auditoria.
  v_tardio := v_pedido.status = 'EXPIRADO' or now() >= v_pedido.reserva_expira_em;
  if v_tardio then
    perform 1 from public.eventos e where e.id = v_pedido.evento_id for update;
    v_disp := private.calcular_disponibilidade_evento(v_pedido.evento_id);
    select count(*) into v_qtd
      from public.ingressos i
     where i.pedido_id = v_pedido.id and i.status in ('RESERVADO', 'EXPIRADO');
  end if;

  update public.pagamentos
     set status = 'APROVADO',
         confirmado_em = now(),
         transacao_id = coalesce(p_transaction_id, transacao_id),
         referencia_externa = coalesce(p_referencia_externa, referencia_externa)
   where id = v_pagamento.id;

  update public.pedidos
     set status = 'PAGO', pago_em = now()
   where id = v_pedido.id;

  update public.ingressos
     set status = 'VALIDO'
   where pedido_id = v_pedido.id and status in ('RESERVADO', 'EXPIRADO');
  get diagnostics v_ingressos = row_count;

  if v_tardio then
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values (null, 'PAGAMENTO_CONFIRMADO_APOS_RESERVA', 'pedidos', v_pedido.id,
      jsonb_build_object('pedido_status', v_pedido.status, 'pagamento_status', v_pagamento.status,
                         'reserva_expira_em', v_pedido.reserva_expira_em),
      jsonb_build_object('ingressos', v_qtd, 'disponibilidade_evento', v_disp,
                         'acima_do_estoque', v_disp < v_qtd));
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'pagamento_id', v_pagamento.id,
    'status', 'PAGO',
    'ingressos_validados', v_ingressos,
    'resultado', case when v_tardio then 'confirmado_apos_reserva' else 'confirmado' end
  );
end;
$$;

-- 3) Lote so encerra por esgotamento quando os pagos atingem a quantidade ----------
create or replace function private.processar_virada_lote_esgotamento(p_evento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_prox public.lotes%rowtype;
  v_disp_lote integer;
  v_disp_evento integer;
  v_pagos integer;
  v_ts timestamptz := now();
begin
  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status = 'CANCELADO' then
    return jsonb_build_object('resultado', 'EVENTO_CANCELADO');
  end if;
  if v_evento.status = 'REALIZADO' then
    return jsonb_build_object('resultado', 'EVENTO_REALIZADO');
  end if;

  select * into v_ativo from public.lotes l
   where l.evento_id = p_evento_id and l.status = 'ATIVO' for update;
  if not found then
    return jsonb_build_object('resultado', 'SEM_LOTE_ATIVO');
  end if;

  v_disp_lote := private.calcular_disponibilidade_lote(v_ativo.id);
  if v_disp_lote > 0 then
    return jsonb_build_object('resultado', 'SEM_VIRADA', 'disponibilidade_lote', v_disp_lote);
  end if;

  v_disp_evento := private.calcular_disponibilidade_evento(p_evento_id);
  if v_disp_evento <= 0 then
    return jsonb_build_object('resultado', 'ESTOQUE_EVENTO_ESGOTADO');
  end if;

  select * into v_prox from public.lotes l
   where l.evento_id = p_evento_id and l.status = 'INATIVO' and l.tipo_ativacao = 'ESGOTAMENTO'
     and l.ordem > v_ativo.ordem
   order by l.ordem asc limit 1 for update;

  if not found then
    -- Sem proximo lote: reservas ainda nao pagas podem vencer e devolver
    -- ingressos. So encerra quando os ingressos PAGOS preenchem o lote.
    select count(*) into v_pagos
      from public.ingressos i
     where i.lote_id = v_ativo.id and i.status in ('VALIDO', 'UTILIZADO');

    if v_pagos < v_ativo.quantidade then
      return jsonb_build_object('resultado', 'ESGOTADO_TEMPORARIO', 'lote_id', v_ativo.id,
                                'pagos', v_pagos, 'quantidade', v_ativo.quantidade);
    end if;

    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    return jsonb_build_object('resultado', 'ESGOTADO_SEM_PROXIMO_LOTE', 'lote_encerrado_id', v_ativo.id);
  end if;

  update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_prox.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (null, 'LOTE_VIRADO_POR_ESGOTAMENTO', 'lotes', v_prox.id,
    jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
    jsonb_build_object('lote_novo_id', v_prox.id, 'lote_novo_ordem', v_prox.ordem, 'ativado_em', v_ts));

  return jsonb_build_object('resultado', 'VIRADO', 'lote_anterior_id', v_ativo.id, 'lote_novo_id', v_prox.id, 'lote_novo_ordem', v_prox.ordem);
end;
$$;

-- 4) Lote encerrado pode ser reativado se ainda tiver ingressos -------------------
create or replace function private.ativar_lote_manual(p_lote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lote public.lotes%rowtype;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_usuario_id uuid;
  v_ts timestamptz := now();
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] registro precisa ser da organizacao ativa
  if not exists (select 1 from public.lotes l where l.id = p_lote_id and l.organizacao_id = (select private.organizacao_atual_id())) then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  select * into v_lote from public.lotes l where l.id = p_lote_id for update;
  if not found then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = v_lote.evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', v_lote.evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite ativacao de lote (status=%)', v_evento.id, v_evento.status using errcode = '23514';
  end if;

  if v_evento.vendas_status <> 'ABERTAS' then
    raise exception 'Vendas encerradas para o evento %', v_evento.id using errcode = '23514';
  end if;

  if v_lote.status = 'ATIVO' then
    return jsonb_build_object('resultado', 'JA_ATIVO', 'lote_ativado_id', v_lote.id, 'lote_ativado_ordem', v_lote.ordem);
  end if;

  if v_lote.status = 'ENCERRADO' and private.calcular_disponibilidade_lote(v_lote.id) <= 0 then
    raise exception 'Lote % esta ENCERRADO e sem ingressos disponiveis', v_lote.id using errcode = '23514';
  end if;

  select * into v_ativo from public.lotes l
   where l.evento_id = v_lote.evento_id and l.status = 'ATIVO' and l.id <> v_lote.id for update;

  if v_ativo.id is not null then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  end if;

  update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_lote.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (v_usuario_id,
    case when v_lote.status = 'ENCERRADO' then 'LOTE_REATIVADO_MANUALMENTE' else 'LOTE_ATIVADO_MANUALMENTE' end,
    'lotes', v_lote.id,
    jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem, 'status_anterior', v_lote.status),
    jsonb_build_object('lote_id', v_lote.id, 'ordem', v_lote.ordem, 'ativado_em', v_ts));

  return jsonb_build_object('resultado', 'ATIVADO', 'lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem, 'lote_ativado_id', v_lote.id, 'lote_ativado_ordem', v_lote.ordem, 'ativado_em', v_ts);
end;
$$;
