-- =============================================================================
-- GZ1 Ingresso - Ponte RPC segura
-- Migration: ponte_rpc_segura
--
-- Arquitetura:
--   public.<rpc>            SECURITY INVOKER (wrapper fino)
--        -> private.<impl>  SECURITY DEFINER (owner postgres)
--             -> tabelas / sequence / funcoes auxiliares
--
-- Escopo desta migration: apenas COMPRA PUBLICA.
--   * criar_reserva
--   * criar_pagamento_pendente
--
-- NAO faz: RLS, policies, revogacao de grants de tabela/sequence, migracao de
-- portaria/admin/sistema. Nao altera regras de negocio.
--
-- SECURITY DEFINER somente no schema private, com SET search_path = '' e
-- objetos schema-qualified. Owner postgres. O schema private NAO esta nos
-- Exposed Schemas (Data API = public, graphql_public).
-- =============================================================================

-- IMPLEMENTACAO PRIVILEGIADA: criar_reserva -----------------------------------
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

-- IMPLEMENTACAO PRIVILEGIADA: criar_pagamento_pendente ------------------------
create or replace function private.criar_pagamento_pendente(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pagamento_id uuid;
begin
  select * into v_pedido
    from public.pedidos p
   where p.id = p_pedido_id
   for update;

  if not found then
    raise exception 'Pedido % nao encontrado', p_pedido_id using errcode = '23503';
  end if;

  if v_pedido.status <> 'RESERVADO' then
    raise exception 'Pedido % nao esta RESERVADO (status=%)', p_pedido_id, v_pedido.status
      using errcode = '23514';
  end if;

  if now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva do pedido % expirada', p_pedido_id using errcode = '23514';
  end if;

  if exists (select 1 from public.pagamentos pg where pg.pedido_id = p_pedido_id) then
    raise exception 'Pedido % ja possui pagamento', p_pedido_id using errcode = '23505';
  end if;

  insert into public.pagamentos (pedido_id, valor, expira_em)
  values (p_pedido_id, v_pedido.valor_total, v_pedido.reserva_expira_em)
  returning id into v_pagamento_id;

  return jsonb_build_object(
    'pagamento_id', v_pagamento_id,
    'pedido_id', p_pedido_id,
    'valor', v_pedido.valor_total,
    'status', 'PENDENTE',
    'expira_em', v_pedido.reserva_expira_em
  );
end;
$$;

-- WRAPPER PUBLICO: criar_reserva ----------------------------------------------
create or replace function public.criar_reserva(
  p_evento_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_comprador_email text default null,
  p_nomes_participantes text[] default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_reserva(
    p_evento_id,
    p_comprador_nome,
    p_comprador_telefone,
    p_comprador_email,
    p_nomes_participantes
  );
$$;

-- WRAPPER PUBLICO: criar_pagamento_pendente -----------------------------------
create or replace function public.criar_pagamento_pendente(p_pedido_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_pagamento_pendente(p_pedido_id);
$$;

-- GRANTS MINIMOS --------------------------------------------------------------
-- USAGE no schema private (necessario para o wrapper INVOKER resolver a chamada).
grant usage on schema private to anon, authenticated;

-- EXECUTE somente nas funcoes private especificas desta migration.
revoke all on function private.criar_reserva(uuid, text, text, text, text[]) from public;
revoke all on function private.criar_pagamento_pendente(uuid) from public;
grant execute on function private.criar_reserva(uuid, text, text, text, text[]) to anon, authenticated;
grant execute on function private.criar_pagamento_pendente(uuid) to anon, authenticated;

-- Helpers de identidade permanecem sem EXECUTE para anon/authenticated.
