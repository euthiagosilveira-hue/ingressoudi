-- =============================================================================
-- GZ1 Ingresso - Automacao de lotes e eventos
-- Migration: automacao_lotes_e_eventos
--
-- Escopo (funcoes de manutencao/transicao; SEM cron/pg_cron):
--   * ativacao manual de lote (admin)
--   * virada por esgotamento
--   * virada por DATA_HORA
--   * inicio de evento (AGENDADO -> EM_ANDAMENTO + vendas encerradas)
--   * encerramento administrativo de evento (EM_ANDAMENTO -> REALIZADO)
--   * expiracao de reservas vencidas (reutiliza expirar_reserva)
--   * funcao central processar_manutencao_eventos()
--   * criar_reserva passa a disparar a virada por esgotamento apos a reserva
--
-- Fora do escopo: RLS, policies, frontend, cron, Mercado Pago, webhook.
-- SECURITY INVOKER (default), SET search_path = '', objetos qualificados.
-- Sem DROP/DELETE/TRUNCATE destrutivo.
--
-- Decisoes documentadas:
--   * DATA_HORA prevalece sobre ESGOTAMENTO (ordem na manutencao).
--   * Multiplos DATA_HORA vencidos: ativa o de MAIOR ordem, desde que a ordem
--     seja maior que a do lote atualmente ativo (sequencia comercial).
--   * Para esgotamento, "estoque global esgotado" -> nao ativa proximo e nao
--     altera o lote atual (retorno ESTOQUE_EVENTO_ESGOTADO).
--   * Somente evento CANCELADO e excluido das automacoes de lote/inicio.
-- =============================================================================

-- ATIVAR LOTE MANUALMENTE (RPC admin) -----------------------------------------
create or replace function public.ativar_lote_manual(
  p_lote_id uuid,
  p_usuario_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_lote public.lotes%rowtype;
  v_evento public.eventos%rowtype;
  v_ativo public.lotes%rowtype;
  v_ts timestamptz := now();
begin
  perform public.validar_operador(p_usuario_id, true);

  select * into v_lote from public.lotes l where l.id = p_lote_id for update;
  if not found then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = v_lote.evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', v_lote.evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite ativacao de lote (status=%)',
      v_evento.id, v_evento.status using errcode = '23514';
  end if;

  if v_evento.vendas_status <> 'ABERTAS' then
    raise exception 'Vendas encerradas para o evento %', v_evento.id using errcode = '23514';
  end if;

  if v_lote.status = 'ENCERRADO' then
    raise exception 'Lote % esta ENCERRADO e nao pode ser reaberto', v_lote.id using errcode = '23514';
  end if;

  select * into v_ativo
    from public.lotes l
   where l.evento_id = v_lote.evento_id
     and l.status = 'ATIVO'
     and l.id <> v_lote.id
   for update;

  if v_ativo.id is not null then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  end if;

  update public.lotes
     set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null
   where id = v_lote.id;

  insert into public.auditoria
    (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values
    (
      p_usuario_id, 'LOTE_ATIVADO_MANUALMENTE', 'lotes', v_lote.id,
      jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
      jsonb_build_object('lote_id', v_lote.id, 'ordem', v_lote.ordem, 'ativado_em', v_ts)
    );

  return jsonb_build_object(
    'resultado', 'ATIVADO',
    'lote_anterior_id', v_ativo.id,
    'lote_anterior_ordem', v_ativo.ordem,
    'lote_ativado_id', v_lote.id,
    'lote_ativado_ordem', v_lote.ordem,
    'ativado_em', v_ts
  );
end;
$$;

-- VIRADA POR ESGOTAMENTO (sistema) --------------------------------------------
create or replace function public.processar_virada_lote_esgotamento(p_evento_id uuid)
returns jsonb
language plpgsql
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
    return jsonb_build_object('resultado', 'NAO_APLICAVEL', 'motivo', 'EVENTO_CANCELADO');
  end if;

  select * into v_ativo
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    return jsonb_build_object('resultado', 'SEM_LOTE_ATIVO');
  end if;

  v_disp_lote := public.calcular_disponibilidade_lote(v_ativo.id);
  if v_disp_lote > 0 then
    return jsonb_build_object('resultado', 'SEM_VIRADA', 'disponibilidade_lote', v_disp_lote);
  end if;

  -- lote esgotado: se o estoque global tambem acabou, nao abre lote novo
  v_disp_evento := public.calcular_disponibilidade_evento(p_evento_id);
  if v_disp_evento <= 0 then
    return jsonb_build_object('resultado', 'ESTOQUE_EVENTO_ESGOTADO');
  end if;

  select * into v_prox
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'INATIVO'
     and l.tipo_ativacao = 'ESGOTAMENTO'
     and l.ordem > v_ativo.ordem
   order by l.ordem asc
   limit 1
   for update;

  if not found then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    return jsonb_build_object('resultado', 'ESGOTADO_SEM_PROXIMO_LOTE', 'lote_encerrado_id', v_ativo.id);
  end if;

  update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
  update public.lotes
     set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null
   where id = v_prox.id;

  insert into public.auditoria
    (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values
    (
      null, 'LOTE_VIRADO_POR_ESGOTAMENTO', 'lotes', v_prox.id,
      jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
      jsonb_build_object('lote_novo_id', v_prox.id, 'lote_novo_ordem', v_prox.ordem, 'ativado_em', v_ts)
    );

  return jsonb_build_object(
    'resultado', 'VIRADO',
    'lote_anterior_id', v_ativo.id,
    'lote_novo_id', v_prox.id,
    'lote_novo_ordem', v_prox.ordem
  );
end;
$$;

-- VIRADA POR DATA/HORA (sistema) ----------------------------------------------
create or replace function public.processar_viradas_lote_por_data(p_evento_id uuid default null)
returns jsonb
language plpgsql
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
     where l.status = 'INATIVO'
       and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now()
       and (p_evento_id is null or l.evento_id = p_evento_id)
  loop
    select * into v_evento from public.eventos e where e.id = v_rec.evento_id for update;

    if v_evento.status = 'CANCELADO' then
      continue;
    end if;

    select * into v_ativo
      from public.lotes l
     where l.evento_id = v_rec.evento_id
       and l.status = 'ATIVO'
     for update;

    v_ordem_ref := coalesce(v_ativo.ordem, 0);

    -- maior ordem entre os DATA_HORA vencidos, a frente do lote ativo
    select * into v_cand
      from public.lotes l
     where l.evento_id = v_rec.evento_id
       and l.status = 'INATIVO'
       and l.tipo_ativacao = 'DATA_HORA'
       and l.ativacao_em <= now()
       and l.ordem > v_ordem_ref
     order by l.ordem desc
     limit 1
     for update;

    if not found then
      continue;
    end if;

    v_ts := now();

    if v_ativo.id is not null then
      update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_ativo.id;
    end if;

    update public.lotes
       set status = 'ATIVO', ativado_em = v_ts, encerrado_em = null
     where id = v_cand.id;

    insert into public.auditoria
      (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values
      (
        null, 'LOTE_VIRADO_POR_DATA', 'lotes', v_cand.id,
        jsonb_build_object('lote_anterior_id', v_ativo.id, 'lote_anterior_ordem', v_ativo.ordem),
        jsonb_build_object('lote_novo_id', v_cand.id, 'lote_novo_ordem', v_cand.ordem, 'ativado_em', v_ts)
      );

    v_viradas := v_viradas || jsonb_build_object(
      'evento_id', v_rec.evento_id,
      'lote_anterior_id', v_ativo.id,
      'lote_novo_id', v_cand.id
    );
  end loop;

  return jsonb_build_object('viradas', v_viradas, 'total', jsonb_array_length(v_viradas));
end;
$$;

-- INICIAR EVENTOS (sistema) ---------------------------------------------------
create or replace function public.processar_inicio_eventos(p_evento_id uuid default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_rec record;
  v_ts timestamptz;
  v_iniciados jsonb := '[]'::jsonb;
begin
  for v_rec in
    select e.id
      from public.eventos e
     where e.status = 'AGENDADO'
       and e.inicio_em <= now()
       and (p_evento_id is null or e.id = p_evento_id)
     order by e.id
     for update
  loop
    v_ts := now();

    update public.eventos
       set status = 'EM_ANDAMENTO', vendas_status = 'ENCERRADAS'
     where id = v_rec.id;

    insert into public.auditoria
      (usuario_id, acao, entidade, entidade_id, dados_novos)
    values
      (
        null, 'EVENTO_INICIADO', 'eventos', v_rec.id,
        jsonb_build_object('status', 'EM_ANDAMENTO', 'vendas_status', 'ENCERRADAS', 'iniciado_em', v_ts)
      );

    v_iniciados := v_iniciados || jsonb_build_object('evento_id', v_rec.id);
  end loop;

  return jsonb_build_object('iniciados', jsonb_array_length(v_iniciados), 'eventos', v_iniciados);
end;
$$;

-- ENCERRAR EVENTO (RPC admin) -------------------------------------------------
create or replace function public.encerrar_evento(
  p_evento_id uuid,
  p_usuario_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_ts timestamptz := now();
begin
  perform public.validar_operador(p_usuario_id, true);

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
    raise exception 'Somente evento EM_ANDAMENTO pode ser encerrado (status=%)',
      v_evento.status using errcode = '23514';
  end if;

  update public.eventos
     set status = 'REALIZADO', encerrado_em = v_ts, vendas_status = 'ENCERRADAS'
   where id = p_evento_id;

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if v_lote.id is not null then
    update public.lotes set status = 'ENCERRADO', encerrado_em = v_ts where id = v_lote.id;
  end if;

  insert into public.auditoria
    (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values
    (
      p_usuario_id, 'EVENTO_ENCERRADO', 'eventos', p_evento_id,
      jsonb_build_object('status_anterior', v_evento.status),
      jsonb_build_object(
        'status', 'REALIZADO', 'encerrado_em', v_ts,
        'vendas_status', 'ENCERRADAS', 'lote_encerrado_id', v_lote.id
      )
    );

  return jsonb_build_object(
    'resultado', 'ENCERRADO',
    'evento_id', p_evento_id,
    'status', 'REALIZADO',
    'encerrado_em', v_ts,
    'lote_encerrado_id', v_lote.id
  );
end;
$$;

-- EXPIRAR RESERVAS VENCIDAS (sistema) -----------------------------------------
-- Reutiliza expirar_reserva. Falha individual aborta a operacao (preferencia).
create or replace function public.processar_reservas_expiradas(p_evento_id uuid default null)
returns jsonb
language plpgsql
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
    v_res := public.expirar_reserva(v_rec.id);
    if (v_res->>'resultado') = 'expirado' then
      v_expirados := v_expirados + 1;
    else
      v_ignorados := v_ignorados + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'processados', v_processados,
    'expirados', v_expirados,
    'ignorados', v_ignorados,
    'erros', 0
  );
end;
$$;

-- MANUTENCAO CENTRAL (sistema) ------------------------------------------------
-- Ordem: reservas -> DATA_HORA -> ESGOTAMENTO -> inicio.
-- DATA_HORA antes de ESGOTAMENTO para garantir precedencia do preco por data.
create or replace function public.processar_manutencao_eventos()
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_reservas jsonb;
  v_data jsonb;
  v_esgotamento jsonb := '[]'::jsonb;
  v_inicio jsonb;
  v_rec record;
begin
  v_reservas := public.processar_reservas_expiradas(null);

  v_data := public.processar_viradas_lote_por_data(null);

  for v_rec in
    select distinct l.evento_id
      from public.lotes l
     where l.status = 'ATIVO'
  loop
    v_esgotamento := v_esgotamento || public.processar_virada_lote_esgotamento(v_rec.evento_id);
  end loop;

  v_inicio := public.processar_inicio_eventos(null);

  return jsonb_build_object(
    'reservas_expiradas', v_reservas,
    'lotes_por_data', v_data,
    'lotes_por_esgotamento', v_esgotamento,
    'eventos_iniciados', v_inicio
  );
end;
$$;

-- CRIAR RESERVA (substituida) -------------------------------------------------
-- Mantem assinatura e comportamento; apos criar ingressos, dispara a virada por
-- esgotamento do evento (mesma transacao; evento/lote ja sob lock reentrante).
create or replace function public.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null
)
returns jsonb
language plpgsql
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
    raise exception 'Quantidade de participantes deve estar entre 1 e 10 (recebido %)', v_qtd
      using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes_participantes) as n(nome)
     where n.nome is null or btrim(n.nome) = ''
  ) then
    raise exception 'Nome de participante nao pode ser vazio' using errcode = '23514';
  end if;

  if p_comprador_nome is null or btrim(p_comprador_nome) = '' then
    raise exception 'comprador_nome obrigatorio' using errcode = '23514';
  end if;

  if p_comprador_telefone is null or btrim(p_comprador_telefone) = '' then
    raise exception 'comprador_telefone obrigatorio' using errcode = '23514';
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status <> 'AGENDADO' then
    raise exception 'Evento % nao esta AGENDADO (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  if v_evento.publicacao_status <> 'PUBLICADO' then
    raise exception 'Evento % nao esta PUBLICADO (publicacao=%)', p_evento_id, v_evento.publicacao_status
      using errcode = '23514';
  end if;

  if v_evento.vendas_status <> 'ABERTAS' then
    raise exception 'Vendas encerradas para o evento % (vendas=%)', p_evento_id, v_evento.vendas_status
      using errcode = '23514';
  end if;

  if now() >= v_evento.inicio_em then
    raise exception 'Evento % ja iniciado', p_evento_id using errcode = '23514';
  end if;

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    raise exception 'Nenhum lote ATIVO para o evento %', p_evento_id using errcode = '23514';
  end if;

  v_disponivel_evento := public.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
      v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := public.calcular_disponibilidade_lote(v_lote.id);
  if v_disponivel_lote < v_qtd then
    raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)',
      v_disponivel_lote, v_qtd using errcode = '23514';
  end if;

  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
  v_valor_unitario := v_lote.preco;
  v_valor_total := v_lote.preco * v_qtd;
  v_reserva_expira_em := now() + interval '15 minutes';

  insert into public.pedidos (
    evento_id, lote_id, codigo,
    comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total,
    status, reserva_expira_em
  ) values (
    p_evento_id, v_lote.id, v_codigo,
    p_comprador_nome, p_comprador_telefone, p_comprador_email,
    v_qtd, 'LOTE', v_valor_unitario, v_valor_total,
    'RESERVADO', v_reserva_expira_em
  )
  returning id into v_pedido_id;

  insert into public.ingressos (
    pedido_id, evento_id, lote_id, codigo,
    participante_nome, valor_unitario, qr_token, status
  )
  select
    v_pedido_id, p_evento_id, v_lote.id,
    v_codigo || '-' || lpad(t.pos::text, 2, '0'),
    btrim(t.nome),
    v_valor_unitario,
    gen_random_uuid()::text,
    'RESERVADO'
  from unnest(p_nomes_participantes) with ordinality as t(nome, pos);

  -- virada imediata por esgotamento (se o lote acabou de esgotar)
  perform public.processar_virada_lote_esgotamento(p_evento_id);

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome
             ) order by i.codigo
           ),
           '[]'::jsonb
         )
    into v_ingressos
    from public.ingressos i
   where i.pedido_id = v_pedido_id;

  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'codigo_pedido', v_codigo,
    'evento_id', p_evento_id,
    'lote_id', v_lote.id,
    'quantidade', v_qtd,
    'valor_unitario', v_valor_unitario,
    'valor_total', v_valor_total,
    'reserva_expira_em', v_reserva_expira_em,
    'status', 'RESERVADO',
    'ingressos', v_ingressos
  );
end;
$$;
