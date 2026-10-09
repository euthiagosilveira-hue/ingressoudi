-- =============================================================================
-- GZ1 Ingresso - Venda manual em dinheiro (ADMINISTRADOR)
-- Migration: venda_manual_admin
--
-- Cria uma operacao administrativa transacional para registrar venda
-- presencial recebida em DINHEIRO. Nao passa por checkout publico, reserva de
-- 30 minutos, Mercado Pago, Stone, webhook ou polling.
--
-- Modelagem:
--   * public.pagamentos.provedor = 'DINHEIRO' (migration anterior adiciona o
--     valor ao enum public.provedor_pagamento).
--   * public.pagamentos.status   = 'APROVADO' (venda recebida na hora).
--   * public.pedidos.status      = 'PAGO' imediatamente (sem estado RESERVADO).
--   * public.pedidos.reserva_expira_em passa a aceitar NULL (nao ha reserva
--     para vender). Nao inventamos timestamp falso: a venda manual nasce paga.
--   * checkout_token permanece NOT NULL com default gen_random_uuid(); a venda
--     manual nao informa nem expoe o token (gerado internamente e nunca usado).
--
-- Regras de evento (documentadas e testadas):
--   * evento precisa existir;
--   * status AGENDADO ou EM_ANDAMENTO permitem venda manual;
--   * status REALIZADO ou CANCELADO bloqueiam;
--   * NAO depende de publicacao_status (operacao administrativa);
--   * NAO depende de vendas_status (controla apenas o canal online). Venda
--     manual segue permitida mesmo com vendas online ENCERRADAS enquanto o
--     evento nao estiver REALIZADO/CANCELADO e houver estoque.
--
-- Regras de lote:
--   * o lote informado precisa pertencer ao evento;
--   * precisa estar ATIVO; lote INATIVO/ENCERRADO e rejeitado;
--   * a disponibilidade (evento e lote) usa private.calcular_disponibilidade_*;
--   * lock SELECT ... FOR UPDATE em evento e lote (mesma ordem do fluxo
--     publico: evento -> lote), sem permitir estoque negativo.
--
-- Preco: sempre de public.lotes.preco no momento da venda. O frontend nao
-- envia valor.
--
-- Superficies:
--   * private.criar_venda_manual_admin(...)          SECURITY DEFINER (admin)
--   * public.criar_venda_manual_admin(...)           SECURITY INVOKER (wrapper)
--   * private.listar_eventos_venda_manual_admin()    SECURITY DEFINER (admin)
--   * public.listar_eventos_venda_manual_admin()     SECURITY INVOKER (wrapper)
--   * public.listar_pedidos_admin(...)               reaplicada com provedor
--
-- Sem DROP/DELETE/TRUNCATE destrutivo. Requer migration anterior aplicada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Pedido pago sem reserva: reserva_expira_em passa a aceitar NULL
-- -----------------------------------------------------------------------------
alter table public.pedidos alter column reserva_expira_em drop not null;

alter table public.pedidos drop constraint if exists chk_pedidos_reserva_expira;
alter table public.pedidos add constraint chk_pedidos_reserva_expira
  check (reserva_expira_em is not null or status in ('PAGO', 'CANCELADO'));

comment on column public.pedidos.reserva_expira_em is
  'Expiracao da reserva (fluxo online). NULL em venda manual paga imediatamente.';

-- -----------------------------------------------------------------------------
-- 2) Listagem admin de pedidos: expor provedor/origem do pagamento
--    (permite identificar "Dinheiro" na listagem sem redesign)
-- -----------------------------------------------------------------------------
create or replace function public.listar_pedidos_admin(
  p_evento_id uuid default null,
  p_busca text default null,
  p_status public.status_pedido default null,
  p_pagamento_status public.status_pagamento default null,
  p_tipo_preco public.tipo_preco_pedido default null,
  p_de timestamptz default null,
  p_ate timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', p.id,
               'codigo', p.codigo,
               'evento_id', p.evento_id,
               'evento_nome', e.nome,
               'lote_id', p.lote_id,
               'lote_nome', l.nome,
               'comprador_nome', p.comprador_nome,
               'comprador_telefone', p.comprador_telefone,
               'comprador_email', p.comprador_email,
               'quantidade', p.quantidade,
               'tipo_preco', p.tipo_preco,
               'valor_unitario', p.valor_unitario,
               'valor_total', p.valor_total,
               'status', p.status,
               'reserva_expira_em', p.reserva_expira_em,
               'pago_em', p.pago_em,
               'cancelado_em', p.cancelado_em,
               'criado_em', p.criado_em,
               'atualizado_em', p.atualizado_em,
               'motivo_valor_avulso', p.motivo_valor_avulso,
               'autorizado_por_nome', u.nome,
               'pagamento_status', pg.status,
               'pagamento_valor', pg.valor,
               'pagamento_provedor', pg.provedor
             )
             order by p.criado_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.pedidos p
    join public.eventos e on e.id = p.evento_id
    left join public.lotes l on l.id = p.lote_id
    left join public.usuarios u on u.id = p.autorizado_por_usuario_id
    left join public.pagamentos pg on pg.pedido_id = p.id
   where (p_evento_id is null or p.evento_id = p_evento_id)
     and (
       p_busca is null or btrim(p_busca) = ''
       or p.codigo ilike '%' || p_busca || '%'
       or p.comprador_nome ilike '%' || p_busca || '%'
       or p.comprador_telefone ilike '%' || p_busca || '%'
       or p.comprador_email ilike '%' || p_busca || '%'
     )
     and (p_status is null or p.status = p_status)
     and (p_pagamento_status is null or pg.status = p_pagamento_status)
     and (p_tipo_preco is null or p.tipo_preco = p_tipo_preco)
     and (p_de is null or p.criado_em >= p_de)
     and (p_ate is null or p.criado_em <= p_ate);

  return v_itens;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3) Listagem admin leve de eventos elegiveis para venda manual
--    Somente AGENDADO/EM_ANDAMENTO; inclui o lote ATIVO (se existir).
-- -----------------------------------------------------------------------------
create or replace function private.listar_eventos_venda_manual_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  return (
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'evento_id', e.id,
                 'nome', e.nome,
                 'inicio_em', e.inicio_em,
                 'local', e.local,
                 'status', e.status,
                 'lote_ativo_id', la.id,
                 'lote_ativo_nome', la.nome,
                 'lote_ativo_preco', la.preco,
                 'lote_ativo_disponiveis',
                   case when la.id is null then null
                        else private.calcular_disponibilidade_lote(la.id)
                   end
               )
               order by e.inicio_em asc
             ),
             '[]'::jsonb
           )
      from public.eventos e
      left join lateral (
        select l.id, l.nome, l.preco
          from public.lotes l
         where l.evento_id = e.id
           and l.status = 'ATIVO'
         order by l.ordem asc
         limit 1
      ) la on true
     where e.status in ('AGENDADO', 'EM_ANDAMENTO')
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4) RPC transacional: registrar venda manual em dinheiro
-- -----------------------------------------------------------------------------
create or replace function private.criar_venda_manual_admin(
  p_evento_id uuid,
  p_lote_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_participantes text[],
  p_comprador_email text default null
)
returns jsonb
language plpgsql
volatile
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
  v_pedido_id uuid;
  v_checkout_token uuid;
  v_pagamento_id uuid;
  v_disponivel_evento integer;
  v_disponivel_lote integer;
  v_ingressos jsonb;
begin
  -- permissao: somente ADMINISTRADOR ativo
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- participantes definem a quantidade
  if p_participantes is null then
    raise exception 'Lista de participantes obrigatoria' using errcode = '22004';
  end if;

  v_qtd := cardinality(p_participantes);

  if v_qtd < 1 or v_qtd > 10 then
    raise exception 'Quantidade de participantes deve estar entre 1 e 10 (recebido %)', v_qtd
      using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_participantes) as n(nome)
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

  -- lock do evento: serializa concorrencia (mesma ordem do fluxo publico)
  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  -- venda manual: permite AGENDADO e EM_ANDAMENTO; bloqueia REALIZADO/CANCELADO.
  -- Nao depende de publicacao_status nem de vendas_status (canal online).
  if v_evento.status not in ('AGENDADO', 'EM_ANDAMENTO') then
    raise exception 'Evento % nao permite venda manual (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  -- lock do lote informado
  select * into v_lote
    from public.lotes l
   where l.id = p_lote_id
   for update;

  if not found then
    raise exception 'Lote % nao encontrado', p_lote_id using errcode = '23503';
  end if;

  if v_lote.evento_id <> p_evento_id then
    raise exception 'Lote % nao pertence ao evento %', p_lote_id, p_evento_id
      using errcode = '23514';
  end if;

  if v_lote.status <> 'ATIVO' then
    raise exception 'Lote % nao esta ATIVO (status=%)', p_lote_id, v_lote.status
      using errcode = '23514';
  end if;

  v_disponivel_evento := private.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
      v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := private.calcular_disponibilidade_lote(p_lote_id);
  if v_disponivel_lote < v_qtd then
    raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)',
      v_disponivel_lote, v_qtd using errcode = '23514';
  end if;

  -- preco SEMPRE do lote no banco; o frontend nao envia valor
  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
  v_valor_unitario := v_lote.preco;
  v_valor_total := v_lote.preco * v_qtd;

  -- pedido nasce PAGO, sem reserva (reserva_expira_em NULL)
  insert into public.pedidos (
    evento_id, lote_id, codigo,
    comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total,
    status, pago_em, reserva_expira_em
  ) values (
    p_evento_id, p_lote_id, v_codigo,
    btrim(p_comprador_nome), btrim(p_comprador_telefone),
    nullif(btrim(coalesce(p_comprador_email, '')), ''),
    v_qtd, 'LOTE', v_valor_unitario, v_valor_total,
    'PAGO', now(), null
  )
  returning id, checkout_token into v_pedido_id, v_checkout_token;

  -- ingressos nascem VALIDO, com QR imprevisivel e valor historico
  insert into public.ingressos (
    pedido_id, evento_id, lote_id, codigo,
    participante_nome, valor_unitario, qr_token, status
  )
  select
    v_pedido_id, p_evento_id, p_lote_id,
    v_codigo || '-' || lpad(t.pos::text, 2, '0'),
    btrim(t.nome),
    v_valor_unitario,
    gen_random_uuid()::text,
    'VALIDO'
  from unnest(p_participantes) with ordinality as t(nome, pos);

  -- pagamento em DINHEIRO aprovado na hora, sem cobranca/externos
  insert into public.pagamentos (pedido_id, provedor, valor, status, confirmado_em)
  values (v_pedido_id, 'DINHEIRO', v_valor_total, 'APROVADO', now())
  returning id into v_pagamento_id;

  -- virada de lote por esgotamento (mesma regra do fluxo publico)
  perform private.processar_virada_lote_esgotamento(p_evento_id);

  -- auditoria (nunca registra qr_token)
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'VENDA_MANUAL_CRIADA',
    'pedidos',
    v_pedido_id,
    jsonb_build_object(
      'pedido_id', v_pedido_id,
      'evento_id', p_evento_id,
      'lote_id', p_lote_id,
      'quantidade', v_qtd,
      'valor_unitario', v_valor_unitario,
      'valor_total', v_valor_total,
      'forma', 'DINHEIRO',
      'admin_usuario_id', auth.uid()
    )
  );

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
    'lote_id', p_lote_id,
    'quantidade', v_qtd,
    'valor_unitario', v_valor_unitario,
    'valor_total', v_valor_total,
    'status', 'PAGO',
    'forma', 'DINHEIRO',
    'pagamento_id', v_pagamento_id,
    'ingressos', v_ingressos
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5) Wrappers publicos (SECURITY INVOKER)
-- -----------------------------------------------------------------------------
create or replace function public.criar_venda_manual_admin(
  p_evento_id uuid,
  p_lote_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_participantes text[],
  p_comprador_email text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_venda_manual_admin(
    p_evento_id, p_lote_id, p_comprador_nome, p_comprador_telefone,
    p_participantes, p_comprador_email
  );
$$;

create or replace function public.listar_eventos_venda_manual_admin()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.listar_eventos_venda_manual_admin();
$$;

-- -----------------------------------------------------------------------------
-- 6) ACL (admin-only via check interno; anon sem EXECUTE)
-- -----------------------------------------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text
) from public;
grant execute on function private.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text
) to authenticated, service_role;

revoke execute on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text
) from public, anon, authenticated, service_role;
grant execute on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text
) to authenticated, service_role;

revoke all on function private.listar_eventos_venda_manual_admin() from public;
grant execute on function private.listar_eventos_venda_manual_admin()
  to authenticated, service_role;

revoke execute on function public.listar_eventos_venda_manual_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.listar_eventos_venda_manual_admin()
  to authenticated, service_role;

revoke execute on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) Documentacao
-- -----------------------------------------------------------------------------
comment on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text
) is 'Registra venda presencial em DINHEIRO (ADMINISTRADOR). Pedido/PIX pulados; pedido PAGO e pagamento APROVADO/DINHEIRO imediatos.';
comment on function public.listar_eventos_venda_manual_admin() is
  'Eventos elegiveis para venda manual (AGENDADO/EM_ANDAMENTO) com lote ATIVO (ADMINISTRADOR).';
comment on function public.listar_pedidos_admin(
  uuid, text, public.status_pedido, public.status_pagamento, public.tipo_preco_pedido, timestamptz, timestamptz
) is 'Listagem administrativa de pedidos (ADMINISTRADOR). Inclui pagamento_provedor. Sem tokens.';
