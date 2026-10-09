-- =============================================================================
-- GZ1 Ingresso - Ponte RPC operacional (portaria, admin, sistema)
-- Migration: ponte_rpc_operacional
--
-- Padrao: public wrapper (SECURITY INVOKER) -> private implementacao
-- (SECURITY DEFINER, owner postgres, search_path=''). Operacoes humanas
-- passam a usar auth.uid() (sem p_usuario_id).
--
-- Escopo:
--   * portaria: registrar_entrada_qr/nome, buscar_ingressos_por_nome
--   * admin:    ativar_lote_manual, encerrar_evento, anular_entrada
--   * sistema:  confirmar_pagamento, expirar_reserva, processar_reservas_expiradas,
--               processar_virada_lote_esgotamento, processar_viradas_lote_por_data,
--               processar_inicio_eventos, processar_manutencao_eventos
--   * disponibilidade movida para private
--   * ACLs minimas; assinaturas legacy revogadas (sem DROP)
--
-- NAO faz: RLS, policies, revogacao de grants de tabela/sequence, frontend.
-- =============================================================================

-- DISPONIBILIDADE (private) ---------------------------------------------------
create or replace function private.calcular_disponibilidade_evento(p_evento_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select e.estoque_antecipado - coalesce((
    select count(*)
      from public.ingressos i
      join public.pedidos p on p.id = i.pedido_id
     where i.evento_id = e.id
       and (
         i.status in ('VALIDO', 'UTILIZADO')
         or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
       )
  ), 0)
  from public.eventos e
  where e.id = p_evento_id;
$$;

create or replace function private.calcular_disponibilidade_lote(p_lote_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select l.quantidade - coalesce((
    select count(*)
      from public.ingressos i
      join public.pedidos p on p.id = i.pedido_id
     where i.lote_id = l.id
       and (
         i.status in ('VALIDO', 'UTILIZADO')
         or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
       )
  ), 0)
  from public.lotes l
  where l.id = p_lote_id;
$$;

-- SISTEMA (private) -----------------------------------------------------------

create or replace function private.expirar_reserva(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_ingressos integer := 0;
  v_pagamentos integer := 0;
begin
  select * into v_pedido from public.pedidos p where p.id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  if v_pedido.status = 'EXPIRADO' then
    return jsonb_build_object('pedido_id', p_pedido_id, 'status', 'EXPIRADO', 'resultado', 'ja_expirado');
  end if;

  if v_pedido.status in ('PAGO', 'CANCELADO') then
    return jsonb_build_object('pedido_id', p_pedido_id, 'status', v_pedido.status, 'resultado', 'nao_aplicavel');
  end if;

  if now() < v_pedido.reserva_expira_em then
    return jsonb_build_object('pedido_id', p_pedido_id, 'status', v_pedido.status, 'resultado', 'ainda_valida');
  end if;

  update public.pedidos set status = 'EXPIRADO' where id = p_pedido_id;

  update public.ingressos set status = 'EXPIRADO'
   where pedido_id = p_pedido_id and status = 'RESERVADO';
  get diagnostics v_ingressos = row_count;

  update public.pagamentos set status = 'EXPIRADO'
   where pedido_id = p_pedido_id and status = 'PENDENTE';
  get diagnostics v_pagamentos = row_count;

  return jsonb_build_object(
    'pedido_id', p_pedido_id, 'status', 'EXPIRADO', 'resultado', 'expirado',
    'ingressos_expirados', v_ingressos, 'pagamentos_expirados', v_pagamentos
  );
end;
$$;

create or replace function private.processar_reservas_expiradas(p_evento_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec record;
  v_res jsonb;
  v_processados integer := 0;
  v_expirados integer := 0;
  v_ignorados integer := 0;
begin
  for v_rec in
    select p.id
      from public.pedidos p
     where p.status = 'RESERVADO'
       and p.reserva_expira_em <= now()
       and (p_evento_id is null or p.evento_id = p_evento_id)
     order by p.id
     for update
  loop
    v_processados := v_processados + 1;
    v_res := private.expirar_reserva(v_rec.id);
    if (v_res->>'resultado') = 'expirado' then
      v_expirados := v_expirados + 1;
    else
      v_ignorados := v_ignorados + 1;
    end if;
  end loop;

  return jsonb_build_object('processados', v_processados, 'expirados', v_expirados, 'ignorados', v_ignorados, 'erros', 0);
end;
$$;

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

create or replace function private.processar_viradas_lote_por_data(p_evento_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec record;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_cand public.lotes%rowtype;
  v_ordem_ref integer;
  v_ts timestamptz;
  v_viradas jsonb := '[]'::jsonb;
begin
  for v_rec in
    select distinct l.evento_id
      from public.lotes l
     where l.status = 'INATIVO' and l.tipo_ativacao = 'DATA_HORA' and l.ativacao_em <= now()
       and (p_evento_id is null or l.evento_id = p_evento_id)
  loop
    select * into v_evento from public.eventos e where e.id = v_rec.evento_id for update;
    if v_evento.status in ('CANCELADO', 'REALIZADO') then
      continue;
    end if;

    select * into v_ativo from public.lotes l
     where l.evento_id = v_rec.evento_id and l.status = 'ATIVO' for update;
    v_ordem_ref := coalesce(v_ativo.ordem, 0);

    select * into v_cand from public.lotes l
     where l.evento_id = v_rec.evento_id and l.status = 'INATIVO' and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now() and l.ordem > v_ordem_ref
     order by l.ordem desc limit 1 for update;
    if not found then
      continue;
    end if;

    v_ts := now();
    if v_ativo.id is not null then
      update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    end if;
    update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_cand.id;

    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values (null, 'LOTE_VIRADO_POR_DATA', 'lotes', v_cand.id,
      jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
      jsonb_build_object('lote_novo_id', v_cand.id, 'lote_novo_ordem', v_cand.ordem, 'ativado_em', v_ts));

    v_viradas := v_viradas || jsonb_build_object('evento_id', v_rec.evento_id, 'lote_anterior_id', v_ativo.id, 'lote_novo_id', v_cand.id);
  end loop;

  return jsonb_build_object('viradas', v_viradas, 'total', jsonb_array_length(v_viradas));
end;
$$;

create or replace function private.processar_inicio_eventos(p_evento_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec record;
  v_ts timestamptz;
  v_iniciados jsonb := '[]'::jsonb;
begin
  for v_rec in
    select e.id from public.eventos e
     where e.status = 'AGENDADO' and e.inicio_em <= now()
       and (p_evento_id is null or e.id = p_evento_id)
     order by e.id for update
  loop
    v_ts := now();
    update public.eventos set status = 'EM_ANDAMENTO', vendas_status = 'ENCERRADAS' where id = v_rec.id;
    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
    values (null, 'EVENTO_INICIADO', 'eventos', v_rec.id,
      jsonb_build_object('status', 'EM_ANDAMENTO', 'vendas_status', 'ENCERRADAS', 'iniciado_em', v_ts));
    v_iniciados := v_iniciados || jsonb_build_object('evento_id', v_rec.id);
  end loop;

  return jsonb_build_object('iniciados', jsonb_array_length(v_iniciados), 'eventos', v_iniciados);
end;
$$;

create or replace function private.processar_manutencao_eventos()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reservas jsonb;
  v_data jsonb;
  v_esgotamento jsonb := '[]'::jsonb;
  v_inicio jsonb;
  v_rec record;
begin
  v_reservas := private.processar_reservas_expiradas(null);
  v_data := private.processar_viradas_lote_por_data(null);

  for v_rec in
    select l.evento_id from public.lotes l
      join public.eventos e on e.id = l.evento_id
     where l.status = 'ATIVO' and e.status not in ('CANCELADO', 'REALIZADO')
     group by l.evento_id
  loop
    v_esgotamento := v_esgotamento || private.processar_virada_lote_esgotamento(v_rec.evento_id);
  end loop;

  v_inicio := private.processar_inicio_eventos(null);

  return jsonb_build_object(
    'reservas_expiradas', v_reservas,
    'lotes_por_data', v_data,
    'lotes_por_esgotamento', v_esgotamento,
    'eventos_iniciados', v_inicio
  );
end;
$$;

create or replace function private.confirmar_pagamento(
  p_pedido_id uuid,
  p_mercado_pago_payment_id text,
  p_mercado_pago_external_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pagamento public.pagamentos%rowtype;
  v_ingressos integer := 0;
begin
  if p_mercado_pago_payment_id is null or btrim(p_mercado_pago_payment_id) = '' then
    raise exception 'mercado_pago_payment_id obrigatorio' using errcode = '23514';
  end if;

  select * into v_pedido from public.pedidos p where p.id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  select * into v_pagamento from public.pagamentos pg where pg.pedido_id = p_pedido_id for update;
  if not found then
    raise exception 'Pagamento do pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  if v_pedido.status = 'PAGO' and v_pagamento.status = 'APROVADO' then
    if v_pagamento.mercado_pago_payment_id = p_mercado_pago_payment_id then
      return jsonb_build_object('pedido_id', p_pedido_id, 'pagamento_id', v_pagamento.id, 'status', 'PAGO', 'resultado', 'ja_confirmado');
    else
      raise exception 'Pedido % ja pago com outro payment_id', p_pedido_id using errcode = '23505';
    end if;
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', p_pedido_id, v_pedido.status using errcode = '23514';
  end if;

  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido % expirada', p_pedido_id using errcode = '23514';
  end if;

  if v_pagamento.status <> 'PENDENTE' then
    raise exception 'Pagamento % nao esta PENDENTE (status=%)', v_pagamento.id, v_pagamento.status using errcode = '23514';
  end if;

  if v_pagamento.valor <> v_pedido.valor_total then
    raise exception 'Pagamento % valor % difere do total % do pedido', v_pagamento.id, v_pagamento.valor, v_pedido.valor_total using errcode = '23514';
  end if;

  update public.pagamentos
     set status = 'APROVADO', confirmado_em = now(),
         mercado_pago_payment_id = p_mercado_pago_payment_id,
         mercado_pago_external_reference = p_mercado_pago_external_reference
   where id = v_pagamento.id;

  update public.pedidos set status = 'PAGO', pago_em = now() where id = p_pedido_id;

  update public.ingressos set status = 'VALIDO'
   where pedido_id = p_pedido_id and status = 'RESERVADO';
  get diagnostics v_ingressos = row_count;

  return jsonb_build_object('pedido_id', p_pedido_id, 'pagamento_id', v_pagamento.id, 'status', 'PAGO', 'ingressos_validados', v_ingressos, 'resultado', 'confirmado');
end;
$$;

-- PORTARIA (private) ----------------------------------------------------------

create or replace function private.processar_entrada(
  p_evento_id uuid,
  p_ingresso_id uuid,
  p_usuario_id uuid,
  p_metodo public.metodo_validacao
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ingresso public.ingressos%rowtype;
  v_evento public.eventos%rowtype;
  v_entrada_ativa public.entradas%rowtype;
  v_ts timestamptz := now();
  v_entrada_id uuid;
begin
  -- identidade: nao confiar no parametro; deve ser auth.uid() de portaria ativa
  if p_usuario_id is null or p_usuario_id <> auth.uid() or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  select * into v_ingresso from public.ingressos i where i.id = p_ingresso_id for update;

  if not found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, p_usuario_id, p_metodo, 'NAO_ENCONTRADO', 'INGRESSO_NAO_ENCONTRADO');
    return jsonb_build_object('resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null, 'participante_nome', null, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso nao encontrado');
  end if;

  if v_ingresso.evento_id <> p_evento_id then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (v_ingresso.evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'EVENTO_INCORRETO', 'INGRESSO_DE_OUTRO_EVENTO');
    return jsonb_build_object('resultado', 'EVENTO_INCORRETO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso pertence a outro evento');
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;

  if v_evento.status = 'CANCELADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'CANCELADO', 'EVENTO_CANCELADO');
    return jsonb_build_object('resultado', 'CANCELADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Evento cancelado');
  elsif v_evento.status = 'REALIZADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'EVENTO_REALIZADO');
    return jsonb_build_object('resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Evento ja realizado');
  elsif v_evento.status = 'AGENDADO' and now() < v_evento.inicio_em then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'EVENTO_NAO_INICIADO');
    return jsonb_build_object('resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Evento ainda nao iniciado');
  end if;

  if v_ingresso.status = 'CANCELADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'CANCELADO', 'INGRESSO_CANCELADO');
    return jsonb_build_object('resultado', 'CANCELADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso cancelado');
  elsif v_ingresso.status = 'EXPIRADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'INGRESSO_EXPIRADO');
    return jsonb_build_object('resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso expirado');
  elsif v_ingresso.status = 'RESERVADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'INGRESSO_NAO_PAGO');
    return jsonb_build_object('resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso ainda nao pago');
  end if;

  select * into v_entrada_ativa from public.entradas en
   where en.ingresso_id = v_ingresso.id and en.anulada_em is null limit 1;

  if found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'JA_UTILIZADO', null);
    return jsonb_build_object('resultado', 'JA_UTILIZADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', v_entrada_ativa.id, 'entrada_em', v_entrada_ativa.entrada_em, 'mensagem', 'Ingresso ja utilizado');
  end if;

  if v_ingresso.status = 'UTILIZADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'JA_UTILIZADO', null);
    return jsonb_build_object('resultado', 'JA_UTILIZADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso ja utilizado');
  end if;

  if v_ingresso.status <> 'VALIDO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'INVALIDO', 'STATUS_NAO_PERMITIDO');
    return jsonb_build_object('resultado', 'INVALIDO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'Ingresso nao esta valido');
  end if;

  insert into public.entradas (ingresso_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_ingresso.id, p_evento_id, p_usuario_id, p_metodo, v_ts)
  returning id into v_entrada_id;

  update public.ingressos set status = 'UTILIZADO', utilizado_em = v_ts where id = v_ingresso.id;

  insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
  values (p_evento_id, v_ingresso.id, p_usuario_id, p_metodo, 'LIBERADO', null);

  return jsonb_build_object('resultado', 'LIBERADO', 'ingresso_id', v_ingresso.id, 'codigo', v_ingresso.codigo, 'participante_nome', v_ingresso.participante_nome, 'entrada_id', v_entrada_id, 'entrada_em', v_ts, 'mensagem', 'Entrada liberada');
end;
$$;

create or replace function private.registrar_entrada_qr(p_evento_id uuid, p_qr_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ingresso public.ingressos%rowtype;
  v_usuario_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if p_qr_token is null or btrim(p_qr_token) = '' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'QR_CODE', 'NAO_ENCONTRADO', 'QR_VAZIO');
    return jsonb_build_object('resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null, 'participante_nome', null, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'QR nao informado');
  end if;

  select * into v_ingresso from public.ingressos i where i.qr_token = p_qr_token;
  if not found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'QR_CODE', 'NAO_ENCONTRADO', 'QR_NAO_ENCONTRADO');
    return jsonb_build_object('resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null, 'participante_nome', null, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'QR nao encontrado');
  end if;

  return private.processar_entrada(p_evento_id, v_ingresso.id, v_usuario_id, 'QR_CODE');
end;
$$;

create or replace function private.registrar_entrada_nome(p_evento_id uuid, p_ingresso_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  return private.processar_entrada(p_evento_id, p_ingresso_id, v_usuario_id, 'NOME');
end;
$$;

create or replace function private.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  return (
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'utilizado_em', i.utilizado_em
               ) order by i.participante_nome, i.codigo
             ),
             '[]'::jsonb
           )
      from public.ingressos i
     where i.evento_id = p_evento_id
       and lower(btrim(i.participante_nome)) = lower(btrim(p_nome))
  );
end;
$$;

-- ADMIN (private) -------------------------------------------------------------

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

  if v_lote.status = 'ENCERRADO' then
    raise exception 'Lote % esta ENCERRADO e nao pode ser reaberto', v_lote.id using errcode = '23514';
  end if;

  select * into v_ativo from public.lotes l
   where l.evento_id = v_lote.evento_id and l.status = 'ATIVO' and l.id <> v_lote.id for update;

  if v_ativo.id is not null then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  end if;

  update public.lotes set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null where id = v_lote.id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (v_usuario_id, 'LOTE_ATIVADO_MANUALMENTE', 'lotes', v_lote.id,
    jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
    jsonb_build_object('lote_id', v_lote.id, 'ordem', v_lote.ordem, 'ativado_em', v_ts));

  return jsonb_build_object('resultado', 'ATIVADO', 'lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem, 'lote_ativado_id', v_lote.id, 'lote_ativado_ordem', v_lote.ordem, 'ativado_em', v_ts);
end;
$$;

create or replace function private.encerrar_evento(p_evento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_usuario_id uuid;
  v_ts timestamptz := now();
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status = 'CANCELADO' then
    raise exception 'Evento % esta CANCELADO', p_evento_id using errcode = '23514';
  end if;

  if v_evento.status = 'REALIZADO' then
    raise exception 'Evento % ja esta REALIZADO', p_evento_id using errcode = '23514';
  end if;

  if v_evento.status <> 'EM_ANDAMENTO' then
    raise exception 'Somente evento EM_ANDAMENTO pode ser encerrado (status=%)', v_evento.status using errcode = '23514';
  end if;

  update public.eventos set status = 'REALIZADO', encerrado_em = v_ts, vendas_status = 'ENCERRADAS' where id = p_evento_id;

  select * into v_lote from public.lotes l where l.evento_id = p_evento_id and l.status = 'ATIVO' for update;
  if v_lote.id is not null then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_lote.id;
  end if;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (v_usuario_id, 'EVENTO_ENCERRADO', 'eventos', p_evento_id,
    jsonb_build_object('status_anterior', v_evento.status),
    jsonb_build_object('status', 'REALIZADO', 'encerrado_em', v_ts, 'vendas_status', 'ENCERRADAS', 'lote_encerrado_id', v_lote.id));

  return jsonb_build_object('resultado', 'ENCERRADO', 'evento_id', p_evento_id, 'status', 'REALIZADO', 'encerrado_em', v_ts, 'lote_encerrado_id', v_lote.id);
end;
$$;

create or replace function private.anular_entrada(p_entrada_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entrada public.entradas%rowtype;
  v_ingresso public.ingressos%rowtype;
  v_outras integer;
  v_usuario_id uuid;
  v_ts timestamptz := now();
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo da anulacao obrigatorio' using errcode = '23514';
  end if;

  select * into v_entrada from public.entradas e where e.id = p_entrada_id for update;
  if not found then
    raise exception 'Entrada % nao encontrada', p_entrada_id using errcode = '23503';
  end if;

  if v_entrada.anulada_em is not null then
    return jsonb_build_object('resultado', 'JA_ANULADA', 'entrada_id', v_entrada.id, 'ingresso_id', v_entrada.ingresso_id, 'mensagem', 'Entrada ja anulada');
  end if;

  select * into v_ingresso from public.ingressos i where i.id = v_entrada.ingresso_id for update;

  update public.entradas
     set anulada_em = v_ts, anulada_por_usuario_id = v_usuario_id, motivo_anulacao = p_motivo
   where id = p_entrada_id;

  select count(*) into v_outras from public.entradas en
   where en.ingresso_id = v_entrada.ingresso_id and en.anulada_em is null and en.id <> p_entrada_id;

  if v_outras = 0 then
    update public.ingressos set status = 'VALIDO', utilizado_em = null where id = v_entrada.ingresso_id;
  end if;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (v_usuario_id, 'ENTRADA_ANULADA', 'entradas', v_entrada.id,
    jsonb_build_object('anulada_em', v_entrada.anulada_em, 'ingresso_id', v_entrada.ingresso_id, 'entrada_em', v_entrada.entrada_em),
    jsonb_build_object('anulada_em', v_ts, 'anulada_por_usuario_id', v_usuario_id, 'motivo_anulacao', p_motivo));

  return jsonb_build_object('resultado', 'ANULADA', 'entrada_id', v_entrada.id, 'ingresso_id', v_entrada.ingresso_id, 'ingresso_status', 'VALIDO', 'anulada_em', v_ts, 'mensagem', 'Entrada anulada');
end;
$$;

-- private.criar_reserva: dependencias passam a ser private ---------------------
create or replace function private.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_qtd integer;
  v_codigo text;
  v_valor_unitario numeric(10, 2);
  v_valor_total numeric(10, 2);
  v_reserva_expira_em timestamptz;
  v_pedido_id uuid;
  v_disponivel_evento integer;
  v_disponivel_lote integer;
  v_ingressos jsonb;
begin
  if p_nomes_participantes is null then
    raise exception 'Lista de participantes obrigatoria' using errcode = '22004';
  end if;

  v_qtd := cardinality(p_nomes_participantes);

  if v_qtd < 1 or v_qtd > 10 then
    raise exception 'Quantidade de participantes deve estar entre 1 e 10 (recebido %)', v_qtd using errcode = '23514';
  end if;

  if exists (select 1 from unnest(p_nomes_participantes) as n(nome) where n.nome is null or btrim(n.nome) = '') then
    raise exception 'Nome de participante nao pode ser vazio' using errcode = '23514';
  end if;

  if p_comprador_nome is null or btrim(p_comprador_nome) = '' then
    raise exception 'comprador_nome obrigatorio' using errcode = '23514';
  end if;

  if p_comprador_telefone is null or btrim(p_comprador_telefone) = '' then
    raise exception 'comprador_telefone obrigatorio' using errcode = '23514';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status <> 'AGENDADO' then
    raise exception 'Evento % nao esta AGENDADO (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  if v_evento.publicacao_status <> 'PUBLICADO' then
    raise exception 'Evento % nao esta PUBLICADO (publicacao=%)', p_evento_id, v_evento.publicacao_status using errcode = '23514';
  end if;

  if v_evento.vendas_status <> 'ABERTAS' then
    raise exception 'Vendas encerradas para o evento % (vendas=%)', p_evento_id, v_evento.vendas_status using errcode = '23514';
  end if;

  if now() >= v_evento.inicio_em then
    raise exception 'Evento % ja iniciado', p_evento_id using errcode = '23514';
  end if;

  select * into v_lote from public.lotes l where l.evento_id = p_evento_id and l.status = 'ATIVO' for update;
  if not found then
    raise exception 'Nenhum lote ATIVO para o evento %', p_evento_id using errcode = '23514';
  end if;

  v_disponivel_evento := private.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)', v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := private.calcular_disponibilidade_lote(v_lote.id);
  if v_disponivel_lote < v_qtd then
    raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)', v_disponivel_lote, v_qtd using errcode = '23514';
  end if;

  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
  v_valor_unitario := v_lote.preco;
  v_valor_total := v_lote.preco * v_qtd;
  v_reserva_expira_em := now() + interval '15 minutes';

  insert into public.pedidos (
    evento_id, lote_id, codigo, comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total, status, reserva_expira_em
  ) values (
    p_evento_id, v_lote.id, v_codigo, p_comprador_nome, p_comprador_telefone, p_comprador_email,
    v_qtd, 'LOTE', v_valor_unitario, v_valor_total, 'RESERVADO', v_reserva_expira_em
  )
  returning id into v_pedido_id;

  insert into public.ingressos (pedido_id, evento_id, lote_id, codigo, participante_nome, valor_unitario, qr_token, status)
  select v_pedido_id, p_evento_id, v_lote.id,
         v_codigo || '-' || lpad(t.pos::text, 2, '0'),
         btrim(t.nome), v_valor_unitario, gen_random_uuid()::text, 'RESERVADO'
  from unnest(p_nomes_participantes) with ordinality as t(nome, pos);

  perform private.processar_virada_lote_esgotamento(p_evento_id);

  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'codigo', i.codigo, 'participante_nome', i.participante_nome) order by i.codigo), '[]'::jsonb)
    into v_ingressos
    from public.ingressos i where i.pedido_id = v_pedido_id;

  return jsonb_build_object(
    'pedido_id', v_pedido_id, 'codigo_pedido', v_codigo, 'evento_id', p_evento_id, 'lote_id', v_lote.id,
    'quantidade', v_qtd, 'valor_unitario', v_valor_unitario, 'valor_total', v_valor_total,
    'reserva_expira_em', v_reserva_expira_em, 'status', 'RESERVADO', 'ingressos', v_ingressos
  );
end;
$$;

-- =============================================================================
-- WRAPPERS PUBLICOS (SECURITY INVOKER)
-- =============================================================================

-- compra
create or replace function public.criar_reserva(
  p_evento_id uuid, p_comprador_nome text, p_comprador_telefone text,
  p_comprador_email text default null, p_nomes_participantes text[] default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.criar_reserva(p_evento_id, p_comprador_nome, p_comprador_telefone, p_comprador_email, p_nomes_participantes); $$;

create or replace function public.criar_pagamento_pendente(p_pedido_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.criar_pagamento_pendente(p_pedido_id); $$;

-- portaria (novas assinaturas sem p_usuario_id)
create or replace function public.registrar_entrada_qr(p_evento_id uuid, p_qr_token text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.registrar_entrada_qr(p_evento_id, p_qr_token); $$;

create or replace function public.registrar_entrada_nome(p_evento_id uuid, p_ingresso_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.registrar_entrada_nome(p_evento_id, p_ingresso_id); $$;

create or replace function public.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.buscar_ingressos_por_nome(p_evento_id, p_nome); $$;

-- admin (novas assinaturas sem p_usuario_id)
create or replace function public.ativar_lote_manual(p_lote_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.ativar_lote_manual(p_lote_id); $$;

create or replace function public.encerrar_evento(p_evento_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.encerrar_evento(p_evento_id); $$;

create or replace function public.anular_entrada(p_entrada_id uuid, p_motivo text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.anular_entrada(p_entrada_id, p_motivo); $$;

-- sistema (mesmas assinaturas)
create or replace function public.confirmar_pagamento(
  p_pedido_id uuid, p_mercado_pago_payment_id text, p_mercado_pago_external_reference text default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.confirmar_pagamento(p_pedido_id, p_mercado_pago_payment_id, p_mercado_pago_external_reference); $$;

create or replace function public.expirar_reserva(p_pedido_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.expirar_reserva(p_pedido_id); $$;

create or replace function public.processar_reservas_expiradas(p_evento_id uuid default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.processar_reservas_expiradas(p_evento_id); $$;

create or replace function public.processar_virada_lote_esgotamento(p_evento_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.processar_virada_lote_esgotamento(p_evento_id); $$;

create or replace function public.processar_viradas_lote_por_data(p_evento_id uuid default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.processar_viradas_lote_por_data(p_evento_id); $$;

create or replace function public.processar_inicio_eventos(p_evento_id uuid default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.processar_inicio_eventos(p_evento_id); $$;

create or replace function public.processar_manutencao_eventos()
returns jsonb language sql security invoker set search_path = ''
as $$ select private.processar_manutencao_eventos(); $$;

-- disponibilidade (wrappers de leitura)
create or replace function public.calcular_disponibilidade_evento(p_evento_id uuid)
returns integer language sql security invoker set search_path = ''
as $$ select private.calcular_disponibilidade_evento(p_evento_id); $$;

create or replace function public.calcular_disponibilidade_lote(p_lote_id uuid)
returns integer language sql security invoker set search_path = ''
as $$ select private.calcular_disponibilidade_lote(p_lote_id); $$;

-- =============================================================================
-- ACL (grants explicitos e minimos)
-- =============================================================================

-- schema private: USAGE para os papeis que executam wrappers INVOKER
grant usage on schema private to anon, authenticated, service_role;

-- COMPRA ----------------------------------------------------------------------
revoke all on function private.criar_reserva(uuid, text, text, text, text[]) from public;
revoke all on function private.criar_pagamento_pendente(uuid) from public;
grant execute on function private.criar_reserva(uuid, text, text, text, text[]) to anon, authenticated, service_role;
grant execute on function private.criar_pagamento_pendente(uuid) to anon, authenticated, service_role;

revoke execute on function public.criar_reserva(uuid, text, text, text, text[]) from public;
revoke execute on function public.criar_pagamento_pendente(uuid) from public;
grant execute on function public.criar_reserva(uuid, text, text, text, text[]) to anon, authenticated, service_role;
grant execute on function public.criar_pagamento_pendente(uuid) to anon, authenticated, service_role;

-- PORTARIA (private + wrappers) ----------------------------------------------
revoke all on function private.registrar_entrada_qr(uuid, text) from public;
revoke all on function private.registrar_entrada_nome(uuid, uuid) from public;
revoke all on function private.buscar_ingressos_por_nome(uuid, text) from public;
revoke all on function private.processar_entrada(uuid, uuid, uuid, public.metodo_validacao) from public;
grant execute on function private.registrar_entrada_qr(uuid, text) to authenticated, service_role;
grant execute on function private.registrar_entrada_nome(uuid, uuid) to authenticated, service_role;
grant execute on function private.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

revoke execute on function public.registrar_entrada_qr(uuid, text) from public;
revoke execute on function public.registrar_entrada_nome(uuid, uuid) from public;
revoke execute on function public.buscar_ingressos_por_nome(uuid, text) from public;
grant execute on function public.registrar_entrada_qr(uuid, text) to authenticated, service_role;
grant execute on function public.registrar_entrada_nome(uuid, uuid) to authenticated, service_role;
grant execute on function public.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;

-- ADMIN (private + wrappers) --------------------------------------------------
revoke all on function private.ativar_lote_manual(uuid) from public;
revoke all on function private.encerrar_evento(uuid) from public;
revoke all on function private.anular_entrada(uuid, text) from public;
grant execute on function private.ativar_lote_manual(uuid) to authenticated, service_role;
grant execute on function private.encerrar_evento(uuid) to authenticated, service_role;
grant execute on function private.anular_entrada(uuid, text) to authenticated, service_role;

revoke execute on function public.ativar_lote_manual(uuid) from public;
revoke execute on function public.encerrar_evento(uuid) from public;
revoke execute on function public.anular_entrada(uuid, text) from public;
grant execute on function public.ativar_lote_manual(uuid) to authenticated, service_role;
grant execute on function public.encerrar_evento(uuid) to authenticated, service_role;
grant execute on function public.anular_entrada(uuid, text) to authenticated, service_role;

-- SISTEMA (private + wrappers) ------------------------------------------------
revoke all on function private.calcular_disponibilidade_evento(uuid) from public;
revoke all on function private.calcular_disponibilidade_lote(uuid) from public;
revoke all on function private.expirar_reserva(uuid) from public;
revoke all on function private.processar_reservas_expiradas(uuid) from public;
revoke all on function private.processar_virada_lote_esgotamento(uuid) from public;
revoke all on function private.processar_viradas_lote_por_data(uuid) from public;
revoke all on function private.processar_inicio_eventos(uuid) from public;
revoke all on function private.processar_manutencao_eventos() from public;
revoke all on function private.confirmar_pagamento(uuid, text, text) from public;

grant execute on function private.calcular_disponibilidade_evento(uuid) to service_role;
grant execute on function private.calcular_disponibilidade_lote(uuid) to service_role;
grant execute on function private.expirar_reserva(uuid) to service_role;
grant execute on function private.processar_reservas_expiradas(uuid) to service_role;
grant execute on function private.processar_virada_lote_esgotamento(uuid) to service_role;
grant execute on function private.processar_viradas_lote_por_data(uuid) to service_role;
grant execute on function private.processar_inicio_eventos(uuid) to service_role;
grant execute on function private.processar_manutencao_eventos() to service_role;
grant execute on function private.confirmar_pagamento(uuid, text, text) to service_role;

revoke execute on function public.calcular_disponibilidade_evento(uuid) from public, anon, authenticated;
revoke execute on function public.calcular_disponibilidade_lote(uuid) from public, anon, authenticated;
revoke execute on function public.confirmar_pagamento(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.expirar_reserva(uuid) from public, anon, authenticated;
revoke execute on function public.processar_reservas_expiradas(uuid) from public, anon, authenticated;
revoke execute on function public.processar_virada_lote_esgotamento(uuid) from public, anon, authenticated;
revoke execute on function public.processar_viradas_lote_por_data(uuid) from public, anon, authenticated;
revoke execute on function public.processar_inicio_eventos(uuid) from public, anon, authenticated;
revoke execute on function public.processar_manutencao_eventos() from public, anon, authenticated;

grant execute on function public.calcular_disponibilidade_evento(uuid) to service_role;
grant execute on function public.calcular_disponibilidade_lote(uuid) to service_role;
grant execute on function public.confirmar_pagamento(uuid, text, text) to service_role;
grant execute on function public.expirar_reserva(uuid) to service_role;
grant execute on function public.processar_reservas_expiradas(uuid) to service_role;
grant execute on function public.processar_virada_lote_esgotamento(uuid) to service_role;
grant execute on function public.processar_viradas_lote_por_data(uuid) to service_role;
grant execute on function public.processar_inicio_eventos(uuid) to service_role;
grant execute on function public.processar_manutencao_eventos() to service_role;

-- LEGACY (com p_usuario_id) — revogado de PUBLIC/anon/authenticated ------------
revoke execute on function public.registrar_entrada_qr(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.registrar_entrada_nome(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.ativar_lote_manual(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.encerrar_evento(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.anular_entrada(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.validar_operador(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.processar_entrada(uuid, uuid, uuid, public.metodo_validacao) from public, anon, authenticated;

grant execute on function public.registrar_entrada_qr(uuid, text, uuid) to service_role;
grant execute on function public.registrar_entrada_nome(uuid, uuid, uuid) to service_role;
grant execute on function public.ativar_lote_manual(uuid, uuid) to service_role;
grant execute on function public.encerrar_evento(uuid, uuid) to service_role;
grant execute on function public.anular_entrada(uuid, uuid, text) to service_role;
grant execute on function public.validar_operador(uuid, boolean) to service_role;
grant execute on function public.processar_entrada(uuid, uuid, uuid, public.metodo_validacao) to service_role;
