-- =============================================================================
-- Ingressoudi - Multiempresa: escopo por organizacao nas RPCs (Etapas B e C)
-- Migration: multiempresa_escopo_rpcs
--
-- Todas as RPCs de administracao e de portaria passam a enxergar e alterar
-- APENAS dados da organizacao ativa do usuario (private.organizacao_atual_id()):
--   * listagens, contadores, dashboard e financeiro filtram por organizacao_id;
--   * operacoes por evento validam o evento ("Evento % nao encontrado");
--   * operacoes por id (lote, VIP, entrada, pedido, ingresso) validam o registro;
--   * portaria: ingresso/VIP de outra organizacao responde NAO_ENCONTRADO,
--     sem expor codigo ou nome do participante;
--   * usuarios: perfil e status passam a ser da organizacao (membros_organizacao).
-- Assinaturas e permissoes (GRANT/REVOKE) das funcoes nao mudam.
-- =============================================================================

-- private.obter_dashboard_evento: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.obter_dashboard_evento(p_evento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
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
$function$;

-- private.criar_venda_manual_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.criar_venda_manual_admin(p_evento_id uuid, p_lote_id uuid, p_comprador_nome text, p_comprador_telefone text, p_participantes text[], p_comprador_email text DEFAULT NULL::text, p_tipo_preco tipo_preco_pedido DEFAULT 'LOTE'::tipo_preco_pedido, p_valor_unitario numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
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
$function$;

-- private.listar_lotes_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.listar_lotes_admin(p_evento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento jsonb;
  v_lotes jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if not exists (select 1 from public.eventos e where e.id = p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select jsonb_build_object(
           'evento_id', e.id,
           'nome', e.nome,
           'status', e.status,
           'vendas_status', e.vendas_status,
           'publicacao_status', e.publicacao_status,
           'inicio_em', e.inicio_em,
           'local', e.local,
           'imagem_url', e.imagem_url,
           'capacidade_total', e.capacidade_total,
           'estoque_antecipado', e.estoque_antecipado,
           'vendidos', (
             select count(*) from public.ingressos i
              where i.evento_id = e.id and i.status in ('VALIDO', 'UTILIZADO')
           ),
           'disponiveis', private.calcular_disponibilidade_evento(e.id)
         )
    into v_evento
    from public.eventos e
   where e.id = p_evento_id;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'lote_id', l.id,
               'nome', l.nome,
               'ordem', l.ordem,
               'quantidade', l.quantidade,
               'preco', l.preco,
               'tipo_ativacao', l.tipo_ativacao,
               'ativacao_em', l.ativacao_em,
               'ativado_em', l.ativado_em,
               'encerrado_em', l.encerrado_em,
               'status', l.status,
               'quantidade_vendida', (
                 select count(*) from public.ingressos i
                  where i.lote_id = l.id and i.status in ('VALIDO', 'UTILIZADO')
               ),
               'quantidade_disponivel', private.calcular_disponibilidade_lote(l.id)
             )
             order by l.ordem asc
           ),
           '[]'::jsonb
         )
    into v_lotes
    from public.lotes l
   where l.evento_id = p_evento_id;

  return jsonb_build_object('evento', v_evento, 'lotes', v_lotes);
end;
$function$;

-- private.criar_lote_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.criar_lote_admin(p_evento_id uuid, p_nome text, p_quantidade integer, p_preco numeric, p_tipo_ativacao tipo_ativacao_lote, p_ativacao_em timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_status_evento public.status_evento;
  v_ordem integer;
  v_ativacao timestamptz;
  v_id uuid;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select e.status into v_status_evento from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_status_evento in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite criar lote (status=%)', p_evento_id, v_status_evento using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do lote' using errcode = '23514';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade deve ser maior que zero' using errcode = '23514';
  end if;
  if p_preco is null or p_preco < 0 then
    raise exception 'O preco deve ser maior ou igual a zero' using errcode = '23514';
  end if;
  if p_tipo_ativacao is null then
    raise exception 'Selecione o tipo de ativacao' using errcode = '23514';
  end if;

  if p_tipo_ativacao = 'DATA_HORA' then
    if p_ativacao_em is null then
      raise exception 'Informe a data e hora de ativacao' using errcode = '23514';
    end if;
    v_ativacao := p_ativacao_em;
  else
    v_ativacao := null;
  end if;

  select coalesce(max(l.ordem), 0) + 1 into v_ordem
    from public.lotes l
   where l.evento_id = p_evento_id;

  insert into public.lotes (evento_id, nome, ordem, quantidade, preco, tipo_ativacao, ativacao_em, status)
  values (p_evento_id, btrim(p_nome), v_ordem, p_quantidade, p_preco, p_tipo_ativacao, v_ativacao, 'INATIVO')
  returning id into v_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'LOTE_CRIADO_ADMIN',
    'lotes',
    v_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'ordem', v_ordem,
      'quantidade', p_quantidade,
      'preco', p_preco,
      'tipo_ativacao', p_tipo_ativacao,
      'ativacao_em', v_ativacao
    )
  );

  return jsonb_build_object(
    'lote_id', v_id,
    'evento_id', p_evento_id,
    'nome', btrim(p_nome),
    'ordem', v_ordem,
    'status', 'INATIVO'
  );
end;
$function$;

-- private.definir_vendas_evento_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.definir_vendas_evento_admin(p_evento_id uuid, p_vendas_status status_vendas)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_anterior public.status_vendas;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if p_vendas_status is null then
    raise exception 'Informe o status de vendas' using errcode = '23514';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar vendas (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  v_anterior := v_evento.vendas_status;

  if v_anterior <> p_vendas_status then
    update public.eventos set vendas_status = p_vendas_status, atualizado_em = now() where id = p_evento_id;

    insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
    values (
      auth.uid(),
      'EVENTO_VENDAS_ALTERADAS',
      'eventos',
      p_evento_id,
      jsonb_build_object('vendas_status', v_anterior),
      jsonb_build_object('vendas_status', p_vendas_status)
    );
  end if;

  return jsonb_build_object('evento_id', p_evento_id, 'vendas_status', p_vendas_status);
end;
$function$;

-- private.obter_evento_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.obter_evento_admin(p_evento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select jsonb_build_object(
           'evento_id', e.id,
           'nome', e.nome,
           'slug', e.slug,
           'descricao', e.descricao,
           'imagem_url', e.imagem_url,
           'inicio_em', e.inicio_em,
           'encerrado_em', e.encerrado_em,
           'local', e.local,
           'endereco', e.endereco,
           'capacidade_total', e.capacidade_total,
           'estoque_antecipado', e.estoque_antecipado,
           'status', e.status,
           'vendas_status', e.vendas_status,
           'publicacao_status', e.publicacao_status,
           'publicado_em', e.publicado_em
         )
    into v_evento
    from public.eventos e
   where e.id = p_evento_id;

  if v_evento is null then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  return v_evento;
end;
$function$;

-- private.atualizar_evento_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.atualizar_evento_admin(p_evento_id uuid, p_nome text, p_slug text, p_descricao text DEFAULT NULL::text, p_imagem_url text DEFAULT NULL::text, p_inicio_em timestamp with time zone DEFAULT NULL::timestamp with time zone, p_local text DEFAULT NULL::text, p_endereco text DEFAULT NULL::text, p_capacidade_total integer DEFAULT NULL::integer, p_estoque_antecipado integer DEFAULT NULL::integer, p_publicacao_status status_publicacao DEFAULT NULL::status_publicacao, p_vendas_status status_vendas DEFAULT NULL::status_vendas)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_slug text;
  v_capacidade integer := coalesce(p_capacidade_total, 0);
  v_estoque integer := coalesce(p_estoque_antecipado, 0);
  v_ocupados integer;
  v_publicado_em timestamptz;
  v_descricao text;
  v_imagem text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao pode ser editado (status=%)', p_evento_id, v_evento.status using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do evento' using errcode = '23514';
  end if;
  if p_local is null or btrim(p_local) = '' then
    raise exception 'Informe o local' using errcode = '23514';
  end if;
  if p_endereco is null or btrim(p_endereco) = '' then
    raise exception 'Informe o endereco' using errcode = '23514';
  end if;
  if p_inicio_em is null then
    raise exception 'Informe a data de inicio' using errcode = '23514';
  end if;
  if v_capacidade <= 0 then
    raise exception 'A capacidade deve ser maior que zero' using errcode = '23514';
  end if;
  if v_estoque < 0 then
    raise exception 'O estoque nao pode ser negativo' using errcode = '23514';
  end if;
  if v_estoque > v_capacidade then
    raise exception 'O estoque nao pode exceder a capacidade total' using errcode = '23514';
  end if;

  if p_imagem_url is not null and btrim(p_imagem_url) ~* '^(blob:|data:)' then
    raise exception 'URL de imagem invalida' using errcode = '23514';
  end if;

  select count(*) into v_ocupados
    from public.ingressos i
    join public.pedidos p on p.id = i.pedido_id
   where i.evento_id = p_evento_id
     and (
       i.status in ('VALIDO', 'UTILIZADO')
       or (i.status = 'RESERVADO' and p.status = 'RESERVADO' and p.reserva_expira_em > now())
     );
  if v_capacidade < v_ocupados then
    raise exception 'A capacidade nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;
  if v_estoque < v_ocupados then
    raise exception 'O estoque nao pode ser menor que os ingressos ja emitidos/reservados (%)', v_ocupados using errcode = '23514';
  end if;

  v_slug := btrim(
    regexp_replace(
      lower(
        translate(
          btrim(coalesce(p_slug, '')),
          U&'\00E1\00E0\00E2\00E3\00E4\00E9\00E8\00EA\00EB\00ED\00EC\00EE\00EF\00F3\00F2\00F4\00F5\00F6\00FA\00F9\00FB\00FC\00E7\00F1',
          'aaaaaeeeeiiiiooooouuuucn'
        )
      ),
      '[^a-z0-9]+', '-', 'g'
    ),
    '-'
  );
  if v_slug = '' then
    raise exception 'Informe o slug' using errcode = '23514';
  end if;

  v_descricao := nullif(btrim(coalesce(p_descricao, '')), '');
  v_imagem := nullif(btrim(coalesce(p_imagem_url, '')), '');

  if exists (
    select 1 from public.eventos e
     where e.slug = v_slug and e.id <> p_evento_id
  ) then
    raise exception 'Ja existe um evento com esse endereco de URL' using errcode = '23505';
  end if;

  v_publicado_em := v_evento.publicado_em;
  if p_publicacao_status = 'PUBLICADO' and v_publicado_em is null then
    v_publicado_em := now();
  end if;

  update public.eventos
     set nome = btrim(p_nome),
         slug = v_slug,
         descricao = v_descricao,
         imagem_url = v_imagem,
         inicio_em = p_inicio_em,
         local = btrim(p_local),
         endereco = btrim(p_endereco),
         capacidade_total = v_capacidade,
         estoque_antecipado = v_estoque,
         publicacao_status = coalesce(p_publicacao_status, publicacao_status),
         publicado_em = v_publicado_em,
         atualizado_em = now()
   where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'EVENTO_ATUALIZADO_ADMIN',
    'eventos',
    p_evento_id,
    jsonb_build_object(
      'nome', v_evento.nome,
      'slug', v_evento.slug,
      'capacidade_total', v_evento.capacidade_total,
      'estoque_antecipado', v_evento.estoque_antecipado,
      'publicacao_status', v_evento.publicacao_status,
      'inicio_em', v_evento.inicio_em
    ),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'slug', v_slug,
      'capacidade_total', v_capacidade,
      'estoque_antecipado', v_estoque,
      'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
      'inicio_em', p_inicio_em
    )
  );

  if p_vendas_status is not null then
    perform private.definir_vendas_evento_admin(p_evento_id, p_vendas_status);
  end if;

  return jsonb_build_object(
    'evento_id', p_evento_id,
    'slug', v_slug,
    'nome', btrim(p_nome),
    'publicacao_status', coalesce(p_publicacao_status, v_evento.publicacao_status),
    'vendas_status', coalesce(p_vendas_status, v_evento.vendas_status)
  );
end;
$function$;

-- private.criar_lista_vip_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.criar_lista_vip_admin(p_evento_id uuid, p_nome text, p_telefone text DEFAULT NULL::text, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_id uuid;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do convidado' using errcode = '23514';
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar a lista VIP (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  insert into public.lista_vip (evento_id, nome, telefone, observacao, criado_por_usuario_id)
  values (
    p_evento_id,
    btrim(p_nome),
    nullif(btrim(coalesce(p_telefone, '')), ''),
    nullif(btrim(coalesce(p_observacao, '')), ''),
    auth.uid()
  )
  returning id into v_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'VIP_ADICIONADO',
    'lista_vip',
    v_id,
    jsonb_build_object('evento_id', p_evento_id, 'nome', btrim(p_nome))
  );

  return jsonb_build_object(
    'vip_id', v_id,
    'evento_id', p_evento_id,
    'nome', btrim(p_nome)
  );
end;
$function$;

-- private.listar_lista_vip_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.listar_lista_vip_admin(p_evento_id uuid, p_busca text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if not exists (select 1 from public.eventos e where e.id = p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'vip_id', lv.id,
               'nome', lv.nome,
               'telefone', lv.telefone,
               'observacao', lv.observacao,
               'entrou', (ev.id is not null),
               'entrada_em', ev.entrada_em,
               'criado_em', lv.criado_em,
               'criado_por', u.nome
             )
             order by lv.nome asc, lv.criado_em asc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.lista_vip lv
    join public.usuarios u on u.id = lv.criado_por_usuario_id
    left join lateral (
      select e.id, e.entrada_em
        from public.entradas_vip e
       where e.lista_vip_id = lv.id
         and e.anulada_em is null
       order by e.entrada_em desc
       limit 1
    ) ev on true
   where lv.evento_id = p_evento_id
     and lv.ativo = true
     and (
       p_busca is null or btrim(p_busca) = ''
       or lv.nome ilike '%' || btrim(p_busca) || '%'
       or lv.telefone ilike '%' || btrim(p_busca) || '%'
     );

  return v_itens;
end;
$function$;

-- private.criar_lista_vip_em_lote_admin: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.criar_lista_vip_em_lote_admin(p_evento_id uuid, p_nomes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_qtd integer;
  v_quantidade integer := 0;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if p_nomes is null or cardinality(p_nomes) < 1 then
    raise exception 'Informe pelo menos um nome' using errcode = '23514';
  end if;

  v_qtd := cardinality(p_nomes);

  if v_qtd > 100 then
    raise exception 'Limite de 100 convidados por inclusao excedido' using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes) as n(nome)
     where n.nome is null or btrim(n.nome) = ''
  ) then
    raise exception 'Ha um nome invalido na lista' using errcode = '23514';
  end if;

  if exists (
    select 1 from unnest(p_nomes) as n(nome)
     where length(btrim(n.nome)) > 120
  ) then
    raise exception 'Nome de convidado muito longo' using errcode = '23514';
  end if;

  -- mesma regra de evento do cadastro individual
  select * into v_evento
    from public.eventos e
   where e.id = p_evento_id
   for update;

  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  if v_evento.status in ('REALIZADO', 'CANCELADO') then
    raise exception 'Evento % nao permite alterar a lista VIP (status=%)', p_evento_id, v_evento.status
      using errcode = '23514';
  end if;

  insert into public.lista_vip (evento_id, nome, telefone, observacao, criado_por_usuario_id)
  select p_evento_id, btrim(n.nome), null, null, auth.uid()
    from unnest(p_nomes) as n(nome);

  get diagnostics v_quantidade = row_count;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    auth.uid(),
    'VIP_LOTE_ADICIONADO',
    'lista_vip',
    p_evento_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'quantidade', v_quantidade,
      'admin_usuario_id', auth.uid()
    )
  );

  return jsonb_build_object('quantidade_criada', v_quantidade);
end;
$function$;

-- private.encerrar_evento: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.encerrar_evento(p_evento_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
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
$function$;

-- private.registrar_entrada_qr: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.registrar_entrada_qr(p_evento_id uuid, p_qr_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ingresso public.ingressos%rowtype;
  v_usuario_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
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

  select * into v_ingresso from public.ingressos i where i.qr_token = p_qr_token and i.organizacao_id = (select private.organizacao_atual_id());
  if not found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'QR_CODE', 'NAO_ENCONTRADO', 'QR_NAO_ENCONTRADO');
    return jsonb_build_object('resultado', 'NAO_ENCONTRADO', 'ingresso_id', null, 'codigo', null, 'participante_nome', null, 'entrada_id', null, 'entrada_em', null, 'mensagem', 'QR nao encontrado');
  end if;

  return private.processar_entrada(p_evento_id, v_ingresso.id, v_usuario_id, 'QR_CODE');
end;
$function$;

-- private.registrar_entrada_nome: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.registrar_entrada_nome(p_evento_id uuid, p_ingresso_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_usuario_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  return private.processar_entrada(p_evento_id, p_ingresso_id, v_usuario_id, 'NOME');
end;
$function$;

-- private.registrar_entrada_vip: evento restrito a organizacao ativa
CREATE OR REPLACE FUNCTION private.registrar_entrada_vip(p_evento_id uuid, p_vip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_vip public.lista_vip%rowtype;
  v_evento public.eventos%rowtype;
  v_entrada public.entradas_vip%rowtype;
  v_usuario_id uuid;
  v_ts timestamptz := now();
  v_entrada_id uuid;
begin
  v_usuario_id := auth.uid();
  if v_usuario_id is null or not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  -- [multiempresa] evento precisa ser da organizacao ativa
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  perform 1 from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;

  -- lock do convidado: serializa tentativas concorrentes
  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
     and lv.organizacao_id = (select private.organizacao_atual_id())
   for update;

  if not found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'NAO_ENCONTRADO', 'VIP_NAO_ENCONTRADO');
    return jsonb_build_object(
      'resultado', 'NAO_ENCONTRADO', 'vip_id', null, 'ingresso_id', null, 'codigo', null,
      'participante_nome', null, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP nao encontrado'
    );
  end if;

  if v_vip.evento_id <> p_evento_id then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (v_vip.evento_id, null, v_usuario_id, 'NOME', 'EVENTO_INCORRETO', 'VIP_DE_OUTRO_EVENTO');
    return jsonb_build_object(
      'resultado', 'EVENTO_INCORRETO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP pertence a outro evento'
    );
  end if;

  if not v_vip.ativo then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'CANCELADO', 'VIP_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Convidado VIP cancelado'
    );
  end if;

  select * into v_evento from public.eventos e where e.id = p_evento_id;

  if v_evento.status = 'CANCELADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'CANCELADO', 'EVENTO_CANCELADO');
    return jsonb_build_object(
      'resultado', 'CANCELADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento cancelado'
    );
  elsif v_evento.status = 'REALIZADO' then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'INVALIDO', 'EVENTO_REALIZADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento ja realizado'
    );
  elsif v_evento.status = 'AGENDADO' and now() < v_evento.inicio_em then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'INVALIDO', 'EVENTO_NAO_INICIADO');
    return jsonb_build_object(
      'resultado', 'INVALIDO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', null, 'entrada_em', null,
      'mensagem', 'Evento ainda nao iniciado'
    );
  end if;

  -- entrada efetiva existente -> dupla entrada
  select * into v_entrada
    from public.entradas_vip ev
   where ev.lista_vip_id = v_vip.id
     and ev.anulada_em is null
   order by ev.entrada_em desc
   limit 1;

  if found then
    insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
    values (p_evento_id, null, v_usuario_id, 'NOME', 'JA_UTILIZADO', 'VIP_JA_UTILIZADO');
    return jsonb_build_object(
      'resultado', 'JA_UTILIZADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
      'participante_nome', v_vip.nome, 'entrada_id', v_entrada.id, 'entrada_em', v_entrada.entrada_em,
      'mensagem', 'Convidado VIP ja registrou entrada'
    );
  end if;

  insert into public.entradas_vip (lista_vip_id, evento_id, usuario_id, metodo_validacao, entrada_em)
  values (v_vip.id, p_evento_id, v_usuario_id, 'NOME', v_ts)
  returning id into v_entrada_id;

  insert into public.tentativas_entrada (evento_id, ingresso_id, usuario_id, metodo_validacao, resultado, motivo)
  values (p_evento_id, null, v_usuario_id, 'NOME', 'LIBERADO', null);

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (
    v_usuario_id,
    'VIP_ENTRADA_REGISTRADA',
    'entradas_vip',
    v_entrada_id,
    jsonb_build_object(
      'evento_id', p_evento_id,
      'lista_vip_id', v_vip.id,
      'entrada_em', v_ts
    )
  );

  return jsonb_build_object(
    'resultado', 'LIBERADO', 'vip_id', v_vip.id, 'ingresso_id', null, 'codigo', null,
    'participante_nome', v_vip.nome, 'entrada_id', v_entrada_id, 'entrada_em', v_ts,
    'mensagem', 'Entrada liberada'
  );
end;
$function$;

-- private.atualizar_lote_admin: lote restrito
CREATE OR REPLACE FUNCTION private.atualizar_lote_admin(p_lote_id uuid, p_nome text, p_quantidade integer, p_preco numeric, p_tipo_ativacao tipo_ativacao_lote, p_ativacao_em timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lote public.lotes%rowtype;
  v_comprometido integer;
  v_tipo public.tipo_ativacao_lote;
  v_ativacao timestamptz;
begin
  if not private.usuario_e_admin() then
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

  if v_lote.status = 'ENCERRADO' then
    raise exception 'Lotes encerrados nao podem ser editados' using errcode = '23514';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do lote' using errcode = '23514';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'A quantidade deve ser maior que zero' using errcode = '23514';
  end if;
  if p_preco is null or p_preco < 0 then
    raise exception 'O preco nao pode ser negativo' using errcode = '23514';
  end if;

  -- Comprometido = quantidade atual - disponibilidade atual (mesma regra do dominio).
  v_comprometido := v_lote.quantidade - coalesce(private.calcular_disponibilidade_lote(p_lote_id), v_lote.quantidade);
  if p_quantidade < v_comprometido then
    raise exception 'A quantidade nao pode ser menor que os ingressos ja comprometidos (%)', v_comprometido
      using errcode = '23514';
  end if;

  if v_lote.status = 'ATIVO' then
    -- Regra de ativacao ja consumida: preserva tipo/ativacao.
    v_tipo := v_lote.tipo_ativacao;
    v_ativacao := v_lote.ativacao_em;
  else
    v_tipo := coalesce(p_tipo_ativacao, v_lote.tipo_ativacao);
    if v_tipo = 'DATA_HORA' then
      if p_ativacao_em is null then
        raise exception 'Informe a data e hora de ativacao' using errcode = '23514';
      end if;
      v_ativacao := p_ativacao_em;
    else
      v_ativacao := null;
    end if;
  end if;

  update public.lotes
     set nome = btrim(p_nome),
         quantidade = p_quantidade,
         preco = p_preco,
         tipo_ativacao = v_tipo,
         ativacao_em = v_ativacao
   where id = p_lote_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'LOTE_ATUALIZADO',
    'lotes',
    p_lote_id,
    jsonb_build_object(
      'nome', v_lote.nome,
      'quantidade', v_lote.quantidade,
      'preco', v_lote.preco,
      'tipo_ativacao', v_lote.tipo_ativacao,
      'ativacao_em', v_lote.ativacao_em
    ),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'quantidade', p_quantidade,
      'preco', p_preco,
      'tipo_ativacao', v_tipo,
      'ativacao_em', v_ativacao
    )
  );

  return jsonb_build_object(
    'lote_id', p_lote_id,
    'evento_id', v_lote.evento_id,
    'nome', btrim(p_nome),
    'ordem', v_lote.ordem,
    'quantidade', p_quantidade,
    'preco', p_preco,
    'tipo_ativacao', v_tipo,
    'ativacao_em', v_ativacao,
    'status', v_lote.status
  );
end;
$function$;

-- private.ativar_lote_manual: lote restrito
CREATE OR REPLACE FUNCTION private.ativar_lote_manual(p_lote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

-- private.atualizar_lista_vip_admin: VIP restrito
CREATE OR REPLACE FUNCTION private.atualizar_lista_vip_admin(p_vip_id uuid, p_nome text, p_telefone text DEFAULT NULL::text, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_vip public.lista_vip%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] registro precisa ser da organizacao ativa
  if not exists (select 1 from public.lista_vip lv where lv.id = p_vip_id and lv.organizacao_id = (select private.organizacao_atual_id())) then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  if p_nome is null or btrim(p_nome) = '' then
    raise exception 'Informe o nome do convidado' using errcode = '23514';
  end if;

  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
   for update;

  if not found then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  if exists (
    select 1 from public.entradas_vip ev
     where ev.lista_vip_id = p_vip_id
       and ev.anulada_em is null
  ) then
    raise exception 'Nao e possivel editar um convidado que ja registrou entrada'
      using errcode = '23514';
  end if;

  update public.lista_vip
     set nome = btrim(p_nome),
         telefone = nullif(btrim(coalesce(p_telefone, '')), ''),
         observacao = nullif(btrim(coalesce(p_observacao, '')), ''),
         atualizado_em = now()
   where id = p_vip_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'VIP_ATUALIZADO',
    'lista_vip',
    p_vip_id,
    jsonb_build_object('nome', v_vip.nome, 'telefone', v_vip.telefone, 'observacao', v_vip.observacao),
    jsonb_build_object(
      'nome', btrim(p_nome),
      'telefone', nullif(btrim(coalesce(p_telefone, '')), ''),
      'observacao', nullif(btrim(coalesce(p_observacao, '')), '')
    )
  );

  return jsonb_build_object('vip_id', p_vip_id, 'nome', btrim(p_nome));
end;
$function$;

-- private.remover_lista_vip_admin: VIP restrito
CREATE OR REPLACE FUNCTION private.remover_lista_vip_admin(p_vip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_vip public.lista_vip%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  -- [multiempresa] registro precisa ser da organizacao ativa
  if not exists (select 1 from public.lista_vip lv where lv.id = p_vip_id and lv.organizacao_id = (select private.organizacao_atual_id())) then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  select * into v_vip
    from public.lista_vip lv
   where lv.id = p_vip_id
   for update;

  if not found then
    raise exception 'Convidado VIP % nao encontrado', p_vip_id using errcode = '23503';
  end if;

  if exists (
    select 1 from public.entradas_vip ev
     where ev.lista_vip_id = p_vip_id
       and ev.anulada_em is null
  ) then
    raise exception 'Nao e possivel remover um convidado que ja registrou entrada'
      using errcode = '23514';
  end if;

  if not v_vip.ativo then
    return jsonb_build_object('vip_id', p_vip_id, 'ativo', false, 'resultado', 'ja_removido');
  end if;

  update public.lista_vip
     set ativo = false, atualizado_em = now()
   where id = p_vip_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos)
  values (
    auth.uid(),
    'VIP_REMOVIDO',
    'lista_vip',
    p_vip_id,
    jsonb_build_object('ativo', true, 'nome', v_vip.nome),
    jsonb_build_object('ativo', false)
  );

  return jsonb_build_object('vip_id', p_vip_id, 'ativo', false, 'resultado', 'removido');
end;
$function$;

-- private.anular_entrada: entrada restrita
CREATE OR REPLACE FUNCTION private.anular_entrada(p_entrada_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- [multiempresa] registro precisa ser da organizacao ativa
  if not exists (select 1 from public.entradas en where en.id = p_entrada_id and en.organizacao_id = (select private.organizacao_atual_id())) then
    raise exception 'Entrada % nao encontrada', p_entrada_id using errcode = '23503';
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
$function$;

-- private.processar_entrada: ingresso de outra organizacao = nao encontrado
CREATE OR REPLACE FUNCTION private.processar_entrada(p_evento_id uuid, p_ingresso_id uuid, p_usuario_id uuid, p_metodo metodo_validacao)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  select * into v_ingresso from public.ingressos i where i.id = p_ingresso_id and i.organizacao_id = (select private.organizacao_atual_id()) for update;

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
$function$;

-- private.buscar_ingressos_por_nome: busca restrita a organizacao ativa
CREATE OR REPLACE FUNCTION private.buscar_ingressos_por_nome(p_evento_id uuid, p_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_alvo text;
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  v_alvo := translate(
    lower(btrim(coalesce(p_nome, ''))),
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  );

  if v_alvo = '' then
    return '[]'::jsonb;
  end if;

  return (
    select coalesce(
             jsonb_agg(item order by item->>'participante_nome', item->>'origem'),
             '[]'::jsonb
           )
      from (
        -- Ingressos normais
        select jsonb_build_object(
                 'origem', 'INGRESSO',
                 'ingresso_id', i.id,
                 'vip_id', null,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'status', i.status,
                 'utilizado_em', i.utilizado_em,
                 'entrada_em', i.utilizado_em,
                 'telefone', (
                   select p.comprador_telefone
                     from public.pedidos p
                    where p.id = i.pedido_id
                 )
               ) as item
          from public.ingressos i
         where i.evento_id = p_evento_id
           and i.organizacao_id = (select private.organizacao_atual_id())
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(i.participante_nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
        union all
        -- Lista VIP (apenas ativos); status derivado da entrada
        select jsonb_build_object(
                 'origem', 'VIP',
                 'ingresso_id', null,
                 'vip_id', lv.id,
                 'codigo', null,
                 'participante_nome', lv.nome,
                 'status', case when ev.id is null then 'VALIDO' else 'UTILIZADO' end,
                 'utilizado_em', ev.entrada_em,
                 'entrada_em', ev.entrada_em,
                 'telefone', lv.telefone
               ) as item
          from public.lista_vip lv
          left join lateral (
            select e.id, e.entrada_em
              from public.entradas_vip e
             where e.lista_vip_id = lv.id
               and e.anulada_em is null
             order by e.entrada_em desc
             limit 1
          ) ev on true
         where lv.evento_id = p_evento_id
           and lv.organizacao_id = (select private.organizacao_atual_id())
           and lv.ativo = true
           and not exists (
             select 1
               from unnest(string_to_array(v_alvo, ' ')) as tok
              where btrim(tok) <> ''
                and position(
                      btrim(tok) in translate(
                        lower(lv.nome),
                        'áàâãäéèêëíìîïóòôõöúùûüçñ',
                        'aaaaaeeeeiiiiooooouuuucn'
                      )
                    ) = 0
           )
      ) t
  );
end;
$function$;

-- private.listar_eventos_portaria: lista restrita
CREATE OR REPLACE FUNCTION private.listar_eventos_portaria()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'evento_id', e.id,
               'nome', e.nome,
               'inicio_em', e.inicio_em,
               'local', e.local,
               'status', e.status
             ) order by e.inicio_em
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.eventos e
   where e.status in ('AGENDADO', 'EM_ANDAMENTO')
     and e.organizacao_id = (select private.organizacao_atual_id());

  return v_itens;
end;
$function$;

-- private.listar_eventos_admin: lista restrita
CREATE OR REPLACE FUNCTION private.listar_eventos_admin()
 RETURNS TABLE(id uuid, nome text, slug text, inicio_em timestamp with time zone, encerrado_em timestamp with time zone, local text, status status_evento, vendas_status status_vendas, publicacao_status status_publicacao, capacidade_total integer, estoque_antecipado integer, criado_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  return query
    select e.id, e.nome, e.slug, e.inicio_em, e.encerrado_em, e.local,
           e.status, e.vendas_status, e.publicacao_status,
           e.capacidade_total, e.estoque_antecipado, e.criado_em
      from public.eventos e
     where e.organizacao_id = (select private.organizacao_atual_id())
     order by e.inicio_em desc;
end;
$function$;

-- private.listar_eventos_admin_filtrado: lista restrita
CREATE OR REPLACE FUNCTION private.listar_eventos_admin_filtrado(p_busca text DEFAULT NULL::text, p_status status_evento DEFAULT NULL::status_evento, p_publicacao status_publicacao DEFAULT NULL::status_publicacao, p_vendas status_vendas DEFAULT NULL::status_vendas)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'evento_id', e.id,
               'nome', e.nome,
               'slug', e.slug,
               'inicio_em', e.inicio_em,
               'local', e.local,
               'status', e.status,
               'vendas_status', e.vendas_status,
               'publicacao_status', e.publicacao_status,
               'capacidade_total', e.capacidade_total,
               'estoque_antecipado', e.estoque_antecipado,
               'publicado_em', e.publicado_em,
               'imagem_url', e.imagem_url,
               'lote_ativo_id', la.id,
               'lote_ativo_nome', la.nome,
               'lote_ativo_ordem', la.ordem,
               'lote_ativo_preco', la.preco,
               'lote_ativo_quantidade', la.quantidade,
               'lote_ativo_vendidos', (
                 select count(*) from public.ingressos i
                  where i.lote_id = la.id and i.status in ('VALIDO', 'UTILIZADO')
               ),
               'lote_ativo_disponiveis', private.calcular_disponibilidade_lote(la.id),
               'lotes_count', (select count(*) from public.lotes l where l.evento_id = e.id),
               'pedidos_count', (select count(*) from public.pedidos p where p.evento_id = e.id),
               'ingressos_count', (select count(*) from public.ingressos i where i.evento_id = e.id)
             )
             order by
               case e.status when 'EM_ANDAMENTO' then 0 when 'AGENDADO' then 1 else 2 end,
               case when e.status in ('REALIZADO', 'CANCELADO') then e.inicio_em end desc nulls last,
               e.inicio_em asc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.eventos e
    left join lateral (
      select l.id, l.nome, l.ordem, l.preco, l.quantidade
        from public.lotes l
       where l.evento_id = e.id and l.status = 'ATIVO'
       order by l.ordem asc
       limit 1
    ) la on true
   where e.organizacao_id = (select private.organizacao_atual_id())
     and (
       p_busca is null or btrim(p_busca) = ''
       or e.nome ilike '%' || p_busca || '%'
       or e.slug ilike '%' || p_busca || '%'
       or e.local ilike '%' || p_busca || '%'
     )
     and (p_status is null or e.status = p_status)
     and (p_publicacao is null or e.publicacao_status = p_publicacao)
     and (p_vendas is null or e.vendas_status = p_vendas);

  return v_itens;
end;
$function$;

-- private.listar_eventos_venda_manual_admin: lista restrita
CREATE OR REPLACE FUNCTION private.listar_eventos_venda_manual_admin()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
       and e.organizacao_id = (select private.organizacao_atual_id())
  );
end;
$function$;

-- public.obter_contadores_admin: contadores restritos
CREATE OR REPLACE FUNCTION public.obter_contadores_admin()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedidos integer;
  v_entradas integer;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select count(*) into v_pedidos
    from public.pedidos p
   where p.organizacao_id = (select private.organizacao_atual_id());

  select count(*) into v_entradas
    from public.entradas en
   where en.anulada_em is null
     and en.organizacao_id = (select private.organizacao_atual_id());

  return jsonb_build_object(
    'pedidos', v_pedidos,
    'entradas', v_entradas
  );
end;
$function$;

-- public.listar_pedidos_admin: lista restrita
CREATE OR REPLACE FUNCTION public.listar_pedidos_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_status status_pedido DEFAULT NULL::status_pedido, p_pagamento_status status_pagamento DEFAULT NULL::status_pagamento, p_tipo_preco tipo_preco_pedido DEFAULT NULL::tipo_preco_pedido, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   where p.organizacao_id = (select private.organizacao_atual_id())
     and (p_evento_id is null or p.evento_id = p_evento_id)
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
$function$;

-- public.listar_ingressos_admin: lista restrita
CREATE OR REPLACE FUNCTION public.listar_ingressos_admin(p_evento_id uuid DEFAULT NULL::uuid, p_pedido_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_status status_ingresso DEFAULT NULL::status_ingresso)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'ingresso_id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'status', i.status,
               'valor_unitario', i.valor_unitario,
               'utilizado_em', i.utilizado_em,
               'criado_em', i.criado_em,
               'pedido_id', i.pedido_id,
               'pedido_codigo', p.codigo,
               'evento_id', i.evento_id,
               'evento_nome', e.nome,
               'evento_inicio_em', e.inicio_em,
               'lote_id', i.lote_id,
               'lote_nome', l.nome
             )
             order by i.criado_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.ingressos i
    join public.pedidos p on p.id = i.pedido_id
    join public.eventos e on e.id = i.evento_id
    left join public.lotes l on l.id = i.lote_id
   where i.organizacao_id = (select private.organizacao_atual_id())
     and (p_evento_id is null or i.evento_id = p_evento_id)
     and (p_pedido_id is null or i.pedido_id = p_pedido_id)
     and (p_status is null or i.status = p_status)
     and (
       p_busca is null or btrim(p_busca) = ''
       or i.codigo ilike '%' || p_busca || '%'
       or i.participante_nome ilike '%' || p_busca || '%'
       or p.codigo ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$function$;

-- public.listar_entradas_admin: lista restrita
CREATE OR REPLACE FUNCTION public.listar_entradas_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_metodo metodo_validacao DEFAULT NULL::metodo_validacao, p_situacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'entrada_id', en.id,
               'entrada_em', en.entrada_em,
               'metodo', en.metodo_validacao,
               'anulada_em', en.anulada_em,
               'anulada_por_nome', ua.nome,
               'motivo_anulacao', en.motivo_anulacao,
               'ingresso_id', i.id,
               'ingresso_codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'ingresso_status', i.status,
               'pedido_id', p.id,
               'pedido_codigo', p.codigo,
               'evento_id', en.evento_id,
               'evento_nome', e.nome,
               'evento_inicio_em', e.inicio_em,
               'operador_id', en.usuario_id,
               'operador_nome', u.nome,
               'criado_em', en.criado_em
             )
             order by en.entrada_em desc
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.entradas en
    join public.ingressos i on i.id = en.ingresso_id
    join public.pedidos p on p.id = i.pedido_id
    join public.eventos e on e.id = en.evento_id
    left join public.usuarios u on u.id = en.usuario_id
    left join public.usuarios ua on ua.id = en.anulada_por_usuario_id
   where en.organizacao_id = (select private.organizacao_atual_id())
     and (p_evento_id is null or en.evento_id = p_evento_id)
     and (p_de is null or en.entrada_em >= p_de)
     and (p_ate is null or en.entrada_em <= p_ate)
     and (p_metodo is null or en.metodo_validacao = p_metodo)
     and (
       p_situacao is null
       or (p_situacao = 'ATIVA' and en.anulada_em is null)
       or (p_situacao = 'ANULADA' and en.anulada_em is not null)
     )
     and (
       p_busca is null or btrim(p_busca) = ''
       or i.codigo ilike '%' || p_busca || '%'
       or i.participante_nome ilike '%' || p_busca || '%'
       or p.codigo ilike '%' || p_busca || '%'
       or u.nome ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$function$;

-- public.obter_financeiro_admin: financeiro restrito
CREATE OR REPLACE FUNCTION public.obter_financeiro_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status_pagamento status_pagamento DEFAULT NULL::status_pagamento, p_provedor provedor_pagamento DEFAULT NULL::provedor_pagamento)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_res jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  with base as (
    select
      pg.id, pg.pedido_id, pg.provedor, pg.status, pg.valor, pg.valor_reembolsado,
      pg.transacao_id, pg.cobranca_id, pg.referencia_externa, pg.expira_em,
      pg.confirmado_em, pg.cancelado_em, pg.reembolsado_em, pg.criado_em,
      p.codigo as pedido_codigo, p.comprador_nome, p.evento_id, e.nome as evento_nome
    from public.pagamentos pg
    join public.pedidos p on p.id = pg.pedido_id
    join public.eventos e on e.id = p.evento_id
    where pg.organizacao_id = (select private.organizacao_atual_id())
      and (p_evento_id is null or p.evento_id = p_evento_id)
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
      )
  )
  select jsonb_build_object(
    'resumo', jsonb_build_object(
      'total', (select count(*) from base),
      'aprovados', (select count(*) from base where status = 'APROVADO'),
      'valorAprovado', (select coalesce(sum(valor), 0) from base where status = 'APROVADO'),
      'pendente', (select coalesce(sum(valor), 0) from base where status = 'PENDENTE'),
      'reembolsado', (select coalesce(sum(valor_reembolsado), 0) from base),
      'liquido', (
        (select coalesce(sum(valor), 0) from base where status = 'APROVADO')
        - (select coalesce(sum(valor_reembolsado), 0) from base)
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
      from base b
    )
  ) into v_res;

  return v_res;
end;
$function$;

-- public.obter_pedido_admin: pedido restrito
CREATE OR REPLACE FUNCTION public.obter_pedido_admin(p_pedido_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pag_json jsonb;
  v_autorizado text;
  v_ingressos jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_pedido from public.pedidos p where p.id = p_pedido_id and p.organizacao_id = (select private.organizacao_atual_id());
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;
  if v_pedido.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_pedido.lote_id;
  end if;
  if v_pedido.autorizado_por_usuario_id is not null then
    select nome into v_autorizado from public.usuarios u where u.id = v_pedido.autorizado_por_usuario_id;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;
  if found then
    v_pag_json := jsonb_build_object(
      'id', v_pag.id,
      'status', v_pag.status,
      'valor', v_pag.valor,
      'provedor', v_pag.provedor,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa,
      'expira_em', v_pag.expira_em,
      'confirmado_em', v_pag.confirmado_em,
      'cancelado_em', v_pag.cancelado_em,
      'reembolsado_em', v_pag.reembolsado_em,
      'valor_reembolsado', v_pag.valor_reembolsado
    );
  else
    v_pag_json := null;
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'valor_unitario', i.valor_unitario,
               'status', i.status,
               'utilizado_em', i.utilizado_em
             ) order by i.codigo
           ),
           '[]'::jsonb
         )
    into v_ingressos
    from public.ingressos i
   where i.pedido_id = v_pedido.id;

  return jsonb_build_object(
    'id', v_pedido.id,
    'codigo', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'comprador_nome', v_pedido.comprador_nome,
    'comprador_telefone', v_pedido.comprador_telefone,
    'comprador_email', v_pedido.comprador_email,
    'quantidade', v_pedido.quantidade,
    'tipo_preco', v_pedido.tipo_preco,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_total', v_pedido.valor_total,
    'status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pago_em', v_pedido.pago_em,
    'cancelado_em', v_pedido.cancelado_em,
    'criado_em', v_pedido.criado_em,
    'atualizado_em', v_pedido.atualizado_em,
    'motivo_valor_avulso', v_pedido.motivo_valor_avulso,
    'autorizado_por_nome', v_autorizado,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'pagamento', v_pag_json,
    'ingressos', v_ingressos
  );
end;
$function$;

-- public.obter_ingresso_admin: ingresso restrito
CREATE OR REPLACE FUNCTION public.obter_ingresso_admin(p_ingresso_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ing public.ingressos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_entrada public.entradas%rowtype;
  v_entrada_json jsonb := null;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select * into v_ing from public.ingressos i where i.id = p_ingresso_id and i.organizacao_id = (select private.organizacao_atual_id());
  if not found then
    return null;
  end if;

  select * into v_pedido from public.pedidos p where p.id = v_ing.pedido_id;
  select * into v_evento from public.eventos e where e.id = v_ing.evento_id;
  if v_ing.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_ing.lote_id;
  end if;

  select * into v_entrada
    from public.entradas en
   where en.ingresso_id = v_ing.id and en.anulada_em is null
   order by en.entrada_em desc
   limit 1;
  if found then
    v_entrada_json := jsonb_build_object(
      'entrada_id', v_entrada.id,
      'entrada_em', v_entrada.entrada_em,
      'metodo', v_entrada.metodo_validacao
    );
  end if;

  return jsonb_build_object(
    'ingresso_id', v_ing.id,
    'codigo', v_ing.codigo,
    'participante_nome', v_ing.participante_nome,
    'status', v_ing.status,
    'valor_unitario', v_ing.valor_unitario,
    'utilizado_em', v_ing.utilizado_em,
    'criado_em', v_ing.criado_em,
    'pedido_id', v_ing.pedido_id,
    'pedido_codigo', v_pedido.codigo,
    'pedido_status', v_pedido.status,
    'evento_id', v_ing.evento_id,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'lote_id', v_ing.lote_id,
    'lote_nome', v_lote.nome,
    'entrada', v_entrada_json
  );
end;
$function$;

-- public.obter_dashboard_admin: dashboard restrito
CREATE OR REPLACE FUNCTION public.obter_dashboard_admin()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_vendidos integer;
  v_utilizados integer;
  v_faturamento numeric;
  v_evento jsonb;
  v_res jsonb;
begin
  v_org := private.organizacao_atual_id();

  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select count(*) filter (where i.status in ('VALIDO', 'UTILIZADO')),
         count(*) filter (where i.status = 'UTILIZADO')
    into v_vendidos, v_utilizados
    from public.ingressos i
   where i.organizacao_id = v_org;

  select coalesce(sum(pg.valor), 0) into v_faturamento
    from public.pagamentos pg where pg.status = 'APROVADO' and pg.organizacao_id = v_org;

  -- Prioridade 1: evento EM_ANDAMENTO (mais recente por inicio_em)
  select to_jsonb(t) into v_evento
    from (
      select e.id as evento_id, e.nome, e.slug, e.imagem_url, e.inicio_em, e.local, e.status
        from public.eventos e
       where e.status = 'EM_ANDAMENTO'
         and e.organizacao_id = v_org
       order by e.inicio_em desc
       limit 1
    ) t;

  -- Prioridade 2: proximo evento AGENDADO futuro (qualquer data, nao so hoje)
  if v_evento is null then
    select to_jsonb(t) into v_evento
      from (
        select e.id as evento_id, e.nome, e.slug, e.imagem_url, e.inicio_em, e.local, e.status
          from public.eventos e
         where e.status = 'AGENDADO' and e.inicio_em >= now()
           and e.organizacao_id = v_org
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
             and en.organizacao_id = v_org
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
        'value', (select count(*) from public.pagamentos where status = 'APROVADO' and organizacao_id = v_org)),
      jsonb_build_object('key', 'pending', 'label', 'Pendente',
        'value', (select count(*) from public.pagamentos where status = 'PENDENTE' and organizacao_id = v_org)),
      jsonb_build_object('key', 'canceled', 'label', 'Cancelado',
        'value', (select count(*) from public.pagamentos where status in ('REJEITADO','CANCELADO','EXPIRADO','REEMBOLSADO') and organizacao_id = v_org))
    ),
    'pedidosRecentes', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.criado_em desc), '[]'::jsonb)
        from (
          select p.id as pedido_id, p.codigo, p.comprador_nome as buyer,
                 p.quantidade as tickets, p.valor_total as total, p.status, p.criado_em,
                 (select count(*) from public.ingressos i where i.pedido_id = p.id and i.status = 'UTILIZADO') as entrance_used
            from public.pedidos p
           where p.organizacao_id = v_org
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
             and en.organizacao_id = v_org
           order by en.entrada_em desc
           limit 5
        ) t
    )
  ) into v_res;

  return v_res;
end;
$function$;

-- public.listar_usuarios_admin: lista apenas os membros da organizacao ativa.
-- perfil e ativo passam a vir de membros_organizacao.
CREATE OR REPLACE FUNCTION public.listar_usuarios_admin(p_busca text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_itens jsonb;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', u.id,
               'nome', u.nome,
               'email', u.email,
               'perfil', m.perfil,
               'ativo', (m.ativo and u.ativo),
               'ultimo_acesso_em', u.ultimo_acesso_em,
               'criado_em', u.criado_em
             )
             order by (m.ativo and u.ativo) desc, m.perfil, u.nome
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.membros_organizacao m
    join public.usuarios u on u.id = m.usuario_id
   where m.organizacao_id = (select private.organizacao_atual_id())
     and (
       p_busca is null
       or btrim(p_busca) = ''
       or u.nome ilike '%' || p_busca || '%'
       or u.email ilike '%' || p_busca || '%'
     );

  return v_itens;
end;
$function$;

-- public.atualizar_usuario_admin: altera o perfil e o status do usuario NA
-- ORGANIZACAO ATIVA (membros_organizacao). O nome continua global.
-- usuarios.ativo (global) nao e mais alterado por administradores de organizacao.
-- usuarios.perfil e mantido em sincronia apenas quando a organizacao ativa do
-- usuario alterado e a mesma (compatibilidade com o front).
CREATE OR REPLACE FUNCTION public.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_membro public.membros_organizacao%rowtype;
  v_nome_anterior text;
  v_nome text;
  v_outros_admins integer;
  v_acao text;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  v_org := private.organizacao_atual_id();

  v_nome := btrim(coalesce(p_nome, ''));
  if v_nome = '' then
    raise exception 'Informe o nome do usuario.' using errcode = '23514';
  end if;

  if p_perfil is null or p_ativo is null then
    raise exception 'Dados invalidos: perfil e status sao obrigatorios.' using errcode = '23514';
  end if;

  select * into v_membro
    from public.membros_organizacao m
   where m.organizacao_id = v_org
     and m.usuario_id = p_usuario_id
   for update;

  if not found then
    raise exception 'Usuario nao encontrado.' using errcode = '23503';
  end if;

  select u.nome into v_nome_anterior from public.usuarios u where u.id = p_usuario_id;

  -- Nunca permitir auto-desativacao
  if p_usuario_id = auth.uid() and p_ativo = false then
    raise exception 'Voce nao pode desativar o seu proprio usuario.' using errcode = '42501';
  end if;

  -- Nunca deixar a organizacao sem ADMINISTRADOR ativo
  if v_membro.perfil = 'ADMINISTRADOR'
     and v_membro.ativo = true
     and (p_ativo = false or p_perfil <> 'ADMINISTRADOR') then
    select count(*) into v_outros_admins
      from public.membros_organizacao m
      join public.usuarios u on u.id = m.usuario_id
     where m.organizacao_id = v_org
       and m.perfil = 'ADMINISTRADOR'
       and m.ativo = true
       and u.ativo = true
       and m.usuario_id <> p_usuario_id;

    if v_outros_admins = 0 then
      raise exception 'E necessario manter pelo menos um administrador ativo.' using errcode = '23514';
    end if;
  end if;

  update public.membros_organizacao
     set perfil = p_perfil,
         ativo = p_ativo
   where organizacao_id = v_org
     and usuario_id = p_usuario_id;

  update public.usuarios u
     set nome = v_nome,
         perfil = case when u.organizacao_ativa_id = v_org then p_perfil else u.perfil end
   where u.id = p_usuario_id;

  v_acao := case
    when v_membro.ativo <> p_ativo and p_ativo then 'USUARIO_ATIVADO'
    when v_membro.ativo <> p_ativo and not p_ativo then 'USUARIO_DESATIVADO'
    when v_membro.perfil <> p_perfil then 'USUARIO_PERFIL_ALTERADO'
    else 'USUARIO_ATUALIZADO'
  end;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (
    auth.uid(),
    v_acao,
    'usuarios',
    p_usuario_id,
    jsonb_build_object('nome', v_nome_anterior, 'perfil', v_membro.perfil, 'ativo', v_membro.ativo),
    jsonb_build_object('nome', v_nome, 'perfil', p_perfil, 'ativo', p_ativo),
    v_org
  );

  return jsonb_build_object('ok', true);
end;
$function$;
