-- =============================================================================
-- GZ1 Ingresso - Venda manual: valor especial (AVULSO) e telefone opcional
-- Migration: venda_manual_valor_especial
--
-- Evolui a venda manual administrativa para dois modos, na MESMA RPC:
--
--   LOTE     : p_lote_id obrigatorio, p_valor_unitario ignorado,
--              preco vem de public.lotes.preco, estoque do lote respeitado.
--              pedido.tipo_preco = 'LOTE'.
--
--   AVULSO   : p_lote_id deve ser null, p_valor_unitario (> 0) obrigatorio,
--              respeita apenas a disponibilidade GLOBAL do evento.
--              pedido.tipo_preco = 'AVULSO', lote_id null,
--              motivo_valor_avulso e autorizado_por_usuario_id preenchidos
--              pelo backend (constraint chk_pedidos_tipo_preco), ingressos
--              sem lote.
--
-- Telefone: opcional em ambos os modos (normalizado vazio -> null).
--
-- Disponibilidade global (AVULSO): private.calcular_disponibilidade_evento ja
-- conta todos os ingressos do evento, independentemente de lote_id, portanto
-- ingressos avulsos consomem o estoque global e evitam overselling.
--
-- Assinatura alterada: DROP controlado das versoes anteriores (nao e possivel
-- CREATE OR REPLACE mudando parametros). Grants reaplicados explicitamente.
--
-- NAO cria enum novo: usa public.tipo_preco_pedido existente (LOTE | AVULSO).
-- Sem DROP/DELETE/TRUNCATE de dados. Requer migration anterior.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Eventos elegiveis: disponibilidade global + lista de lotes ATIVOS
--    (lotes_ativos como array para suportar mais de um lote ativo no futuro)
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
                 'estoque_antecipado', e.estoque_antecipado,
                 'disponiveis_evento', private.calcular_disponibilidade_evento(e.id),
                 'lotes_ativos', coalesce((
                   select jsonb_agg(
                            jsonb_build_object(
                              'id', l.id,
                              'nome', l.nome,
                              'preco', l.preco,
                              'disponiveis', private.calcular_disponibilidade_lote(l.id)
                            ) order by l.ordem asc
                          )
                     from public.lotes l
                    where l.evento_id = e.id
                      and l.status = 'ATIVO'
                 ), '[]'::jsonb)
               )
               order by e.inicio_em asc
             ),
             '[]'::jsonb
           )
      from public.eventos e
     where e.status in ('AGENDADO', 'EM_ANDAMENTO')
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 2) DROP das versoes anteriores (assinatura muda)
-- -----------------------------------------------------------------------------
drop function if exists public.criar_venda_manual_admin(uuid, uuid, text, text, text[], text);
drop function if exists private.criar_venda_manual_admin(uuid, uuid, text, text, text[], text);

-- -----------------------------------------------------------------------------
-- 3) RPC transacional unica: venda por lote OU valor especial (AVULSO)
-- -----------------------------------------------------------------------------
create or replace function private.criar_venda_manual_admin(
  p_evento_id uuid,
  p_lote_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_participantes text[],
  p_comprador_email text default null,
  p_tipo_preco public.tipo_preco_pedido default 'LOTE',
  p_valor_unitario numeric default null
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
  v_tipo public.tipo_preco_pedido;
  v_qtd integer;
  v_codigo text;
  v_lote_id uuid;
  v_valor_unitario numeric(10, 2);
  v_valor_total numeric(10, 2);
  v_motivo_avulso text;
  v_autorizado uuid;
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

  v_tipo := coalesce(p_tipo_preco, 'LOTE');

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

  -- telefone OPCIONAL: vazio normalizado para null no insert

  -- lock do evento: serializa concorrencia e protege o estoque global
  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  -- venda manual: AGENDADO/EM_ANDAMENTO; bloqueia REALIZADO/CANCELADO.
  -- Nao depende de publicacao_status nem de vendas_status.
  if v_evento.status not in ('AGENDADO', 'EM_ANDAMENTO') then
    raise exception 'Evento % nao permite venda manual (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  v_disponivel_evento := private.calcular_disponibilidade_evento(p_evento_id);

  if v_tipo = 'LOTE' then
    if p_lote_id is null then
      raise exception 'Lote obrigatorio na venda por lote' using errcode = '23514';
    end if;

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

    if v_disponivel_evento < v_qtd then
      raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
        v_disponivel_evento, v_qtd using errcode = '23514';
    end if;

    v_disponivel_lote := private.calcular_disponibilidade_lote(p_lote_id);
    if v_disponivel_lote < v_qtd then
      raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)',
        v_disponivel_lote, v_qtd using errcode = '23514';
    end if;

    -- preco SEMPRE do lote; valor enviado pelo frontend e ignorado
    v_lote_id := p_lote_id;
    v_valor_unitario := v_lote.preco;
    v_motivo_avulso := null;
    v_autorizado := null;
  elsif v_tipo = 'AVULSO' then
    -- valor especial: sem lote, valor informado pelo admin, estoque global
    if p_lote_id is not null then
      raise exception 'Venda com valor especial nao pode ter lote' using errcode = '23514';
    end if;

    if p_valor_unitario is null or p_valor_unitario <= 0 then
      raise exception 'Informe um valor unitario maior que zero' using errcode = '23514';
    end if;

    if v_disponivel_evento < v_qtd then
      raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
        v_disponivel_evento, v_qtd using errcode = '23514';
    end if;

    v_lote_id := null;
    v_valor_unitario := round(p_valor_unitario, 2);
    -- constraint chk_pedidos_tipo_preco exige motivo e autorizador em AVULSO
    v_motivo_avulso := 'Venda manual - valor especial (DINHEIRO)';
    v_autorizado := auth.uid();
  else
    raise exception 'Tipo de venda invalido (%)', v_tipo using errcode = '23514';
  end if;

  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
  v_valor_total := v_valor_unitario * v_qtd;

  -- pedido nasce PAGO, sem reserva (reserva_expira_em NULL)
  insert into public.pedidos (
    evento_id, lote_id, codigo,
    comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total,
    motivo_valor_avulso, autorizado_por_usuario_id,
    status, pago_em, reserva_expira_em
  ) values (
    p_evento_id, v_lote_id, v_codigo,
    btrim(p_comprador_nome),
    nullif(btrim(coalesce(p_comprador_telefone, '')), ''),
    nullif(btrim(coalesce(p_comprador_email, '')), ''),
    v_qtd, v_tipo, v_valor_unitario, v_valor_total,
    v_motivo_avulso, v_autorizado,
    'PAGO', now(), null
  )
  returning id, checkout_token into v_pedido_id, v_checkout_token;

  -- ingressos nascem VALIDO; lote_id reflete o modo (null em AVULSO)
  insert into public.ingressos (
    pedido_id, evento_id, lote_id, codigo,
    participante_nome, valor_unitario, qr_token, status
  )
  select
    v_pedido_id, p_evento_id, v_lote_id,
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

  -- virada de lote por esgotamento somente no modo LOTE
  if v_tipo = 'LOTE' then
    perform private.processar_virada_lote_esgotamento(p_evento_id);
  end if;

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
      'lote_id', v_lote_id,
      'tipo_preco', v_tipo,
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
    'lote_id', v_lote_id,
    'tipo_preco', v_tipo,
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
-- 4) Wrapper publico (SECURITY INVOKER)
-- -----------------------------------------------------------------------------
create or replace function public.criar_venda_manual_admin(
  p_evento_id uuid,
  p_lote_id uuid,
  p_comprador_nome text,
  p_comprador_telefone text,
  p_participantes text[],
  p_comprador_email text default null,
  p_tipo_preco public.tipo_preco_pedido default 'LOTE',
  p_valor_unitario numeric default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_venda_manual_admin(
    p_evento_id, p_lote_id, p_comprador_nome, p_comprador_telefone,
    p_participantes, p_comprador_email, p_tipo_preco, p_valor_unitario
  );
$$;

-- -----------------------------------------------------------------------------
-- 5) ACL
-- -----------------------------------------------------------------------------
grant usage on schema private to authenticated, service_role;

revoke all on function private.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric
) from public;
grant execute on function private.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric
) to authenticated, service_role;

revoke execute on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric
) from public, anon, authenticated, service_role;
grant execute on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric
) to authenticated, service_role;

revoke all on function private.listar_eventos_venda_manual_admin() from public;
grant execute on function private.listar_eventos_venda_manual_admin()
  to authenticated, service_role;

revoke execute on function public.listar_eventos_venda_manual_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.listar_eventos_venda_manual_admin()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6) Documentacao
-- -----------------------------------------------------------------------------
comment on function public.criar_venda_manual_admin(
  uuid, uuid, text, text, text[], text, public.tipo_preco_pedido, numeric
) is 'Venda presencial em DINHEIRO (ADMINISTRADOR). Modo LOTE (preco do lote) ou AVULSO (valor especial, sem lote, estoque global). Pedido PAGO e pagamento APROVADO/DINHEIRO imediatos.';
comment on function public.listar_eventos_venda_manual_admin() is
  'Eventos elegiveis para venda manual (AGENDADO/EM_ANDAMENTO) com disponibilidade global e lotes ATIVOS (ADMINISTRADOR).';
