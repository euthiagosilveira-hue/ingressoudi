-- =============================================================================
-- Ingressoudi - Meia-entrada por evento (Lei 12.933/2013)
--  * eventos.meia_entrada_ativa: o produtor liga a meia-entrada no evento.
--  * ingressos.meia: cada ingresso e inteira ou meia. Meia = 50% do preco do
--    lote (arredondado em centavos). A taxa de servico por ingresso nao muda.
--  * criar_reserva recebe p_meias (um boolean por participante, opcional).
--  * O comprador comprova o direito na entrada: checkout, ingresso e portaria
--    mostram "Meia-entrada".
--  * pedidos.valor_unitario continua sendo o preco da INTEIRA (historico do lote);
--    o valor de cada ingresso fica em ingressos.valor_unitario.
-- =============================================================================

-- 1) COLUNAS -----------------------------------------------------------------------
alter table public.eventos
  add column meia_entrada_ativa boolean not null default false;

alter table public.ingressos
  add column meia boolean not null default false;

-- Preco da meia a partir do preco da inteira (uma unica regra para todo o banco).
create or replace function private.preco_meia(p_preco numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$ select round(coalesce(p_preco, 0) / 2, 2); $$;

revoke all on function private.preco_meia(numeric) from public, anon;
grant execute on function private.preco_meia(numeric) to authenticated, service_role;

-- 2) CONSISTENCIA DO INGRESSO: aceita o valor da meia ------------------------------
create or replace function public.validar_ingresso_consistencia()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_evento_id uuid;
  v_lote_id uuid;
  v_tipo public.tipo_preco_pedido;
  v_valor_unitario numeric(10, 2);
  v_quantidade integer;
  v_total_ingressos integer;
begin
  -- Bloqueia a linha do pedido: evita corrida na checagem de quantidade.
  select p.evento_id, p.lote_id, p.tipo_preco, p.valor_unitario, p.quantidade
    into v_evento_id, v_lote_id, v_tipo, v_valor_unitario, v_quantidade
    from public.pedidos p
   where p.id = new.pedido_id
   for update;

  if not found then
    raise exception
      'Ingresso % : pedido % nao encontrado',
      new.id, new.pedido_id
      using errcode = '23503';
  end if;

  -- evento do ingresso deve coincidir com o do pedido
  if new.evento_id <> v_evento_id then
    raise exception
      'Ingresso % : evento % difere do evento % do pedido %',
      new.id, new.evento_id, v_evento_id, new.pedido_id
      using errcode = '23514';
  end if;

  if new.meia and v_tipo <> 'LOTE' then
    raise exception
      'Ingresso % : meia-entrada so existe em pedido de lote',
      new.id
      using errcode = '23514';
  end if;

  if v_tipo = 'LOTE' then
    if new.lote_id is null or new.lote_id <> v_lote_id then
      raise exception
        'Ingresso % : lote % incompativel com o lote % do pedido %',
        new.id, new.lote_id, v_lote_id, new.pedido_id
        using errcode = '23514';
    end if;
  else
    -- AVULSO
    if new.lote_id is not null then
      raise exception
        'Ingresso % : pedido avulso nao pode ter lote',
        new.id
        using errcode = '23514';
    end if;
  end if;

  -- se houver lote, ele deve ser do mesmo evento do ingresso
  if new.lote_id is not null then
    perform 1
      from public.lotes l
     where l.id = new.lote_id
       and l.evento_id = new.evento_id;

    if not found then
      raise exception
        'Ingresso % : lote % nao pertence ao evento %',
        new.id, new.lote_id, new.evento_id
        using errcode = '23514';
    end if;
  end if;

  -- valor unitario deve bater com o pedido (fonte historica); meia = metade
  if new.valor_unitario <> (case when new.meia then private.preco_meia(v_valor_unitario) else v_valor_unitario end) then
    raise exception
      'Ingresso % : valor_unitario % difere do valor % do pedido %',
      new.id, new.valor_unitario, v_valor_unitario, new.pedido_id
      using errcode = '23514';
  end if;

  -- quantidade de ingressos nao pode exceder a quantidade do pedido
  select count(*)
    into v_total_ingressos
    from public.ingressos i
   where i.pedido_id = new.pedido_id
     and i.id <> new.id;

  if v_total_ingressos + 1 > v_quantidade then
    raise exception
      'Pedido % : limite de % ingressos excedido (ja existem %)',
      new.pedido_id, v_quantidade, v_total_ingressos
      using errcode = '23514';
  end if;

  return new;
end;
$$;

-- 3) RESERVA COM MEIA-ENTRADA ------------------------------------------------------
-- Assinatura nova (p_meias): remove a antiga para nao haver sobrecarga ambigua.
drop function public.criar_reserva(uuid, text, text, text, text[]);
drop function private.criar_reserva(uuid, text, text, text, text[]);

CREATE FUNCTION private.criar_reserva(p_evento_id uuid, p_comprador_nome text, p_comprador_telefone text, p_comprador_email text DEFAULT NULL::text, p_nomes_participantes text[] DEFAULT NULL::text[], p_meias boolean[] DEFAULT NULL::boolean[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_evento public.eventos%rowtype;
  v_lote public.lotes%rowtype;
  v_qtd integer;
  v_codigo text;
  v_valor_unitario numeric(10, 2);
  v_valor_total numeric(10, 2);
  v_reserva_expira_em timestamptz;
  v_pedido_id uuid;
  v_checkout_token uuid;
  v_disponivel_evento integer;
  v_disponivel_lote integer;
  v_ingressos jsonb;
  v_taxa_unitaria numeric(10, 2);
  v_valor_ingressos numeric(10, 2);
  v_valor_taxa numeric(10, 2);
  v_qtd_meia integer := 0;
  v_preco_meia numeric(10, 2);
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

  if p_meias is not null then
    if cardinality(p_meias) <> v_qtd then
      raise exception 'Lista de meia-entrada difere dos participantes (participantes=%, meias=%)',
        v_qtd, cardinality(p_meias) using errcode = '23514';
    end if;
    select count(*) into v_qtd_meia from unnest(p_meias) as m(meia) where m.meia;
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

  if v_qtd_meia > 0 and not v_evento.meia_entrada_ativa then
    raise exception 'Meia-entrada nao disponivel para o evento %', p_evento_id using errcode = '23514';
  end if;

  select * into v_lote
    from public.lotes l
   where l.evento_id = p_evento_id
     and l.status = 'ATIVO'
   for update;

  if not found then
    raise exception 'Nenhum lote ATIVO para o evento %', p_evento_id using errcode = '23514';
  end if;

  v_disponivel_evento := private.calcular_disponibilidade_evento(p_evento_id);
  if v_disponivel_evento < v_qtd then
    raise exception 'Estoque insuficiente no evento (disponivel=%, solicitado=%)',
      v_disponivel_evento, v_qtd using errcode = '23514';
  end if;

  v_disponivel_lote := private.calcular_disponibilidade_lote(v_lote.id);
  if v_disponivel_lote < v_qtd then
    raise exception 'Limite do lote insuficiente (disponivel=%, solicitado=%)',
      v_disponivel_lote, v_qtd using errcode = '23514';
  end if;

  v_codigo := private.gerar_codigo_pedido();
  v_valor_unitario := v_lote.preco;
  v_preco_meia := private.preco_meia(v_lote.preco);
  v_valor_ingressos := v_lote.preco * (v_qtd - v_qtd_meia) + v_preco_meia * v_qtd_meia;

  -- [Fase 2A] taxa de servico da plataforma (valor fixo por ingresso da organizacao)
  select o.taxa_servico into v_taxa_unitaria
    from public.organizacoes o
   where o.id = v_evento.organizacao_id;
  v_taxa_unitaria := coalesce(v_taxa_unitaria, 0);

  if v_evento.taxa_repassada then
    -- comprador paga ingresso + taxa
    v_valor_taxa := v_taxa_unitaria * v_qtd;
    v_valor_total := v_valor_ingressos + v_valor_taxa;
  else
    -- produtor absorve: a taxa sai do valor do ingresso (nunca maior que ele)
    v_taxa_unitaria := least(
      v_taxa_unitaria,
      case when v_qtd_meia > 0 then v_preco_meia else v_lote.preco end
    );
    v_valor_taxa := v_taxa_unitaria * v_qtd;
    v_valor_total := v_valor_ingressos;
  end if;
  v_reserva_expira_em := now() + interval '30 minutes';

  insert into public.pedidos (
    evento_id, lote_id, codigo,
    comprador_nome, comprador_telefone, comprador_email,
    quantidade, tipo_preco, valor_unitario, valor_total,
    status, reserva_expira_em,
    taxa_servico_unitaria, taxa_repassada, valor_taxa_total
  ) values (
    p_evento_id, v_lote.id, v_codigo,
    p_comprador_nome, p_comprador_telefone, p_comprador_email,
    v_qtd, 'LOTE', v_valor_unitario, v_valor_total,
    'RESERVADO', v_reserva_expira_em,
    v_taxa_unitaria, v_evento.taxa_repassada, v_valor_taxa
  )
  returning id, checkout_token into v_pedido_id, v_checkout_token;

  insert into public.ingressos (
    pedido_id, evento_id, lote_id, codigo,
    participante_nome, valor_unitario, qr_token, status, meia
  )
  select
    v_pedido_id, p_evento_id, v_lote.id,
    v_codigo || '-' || lpad(t.pos::text, 2, '0'),
    btrim(t.nome),
    case when coalesce(p_meias[t.pos], false) then v_preco_meia else v_valor_unitario end,
    gen_random_uuid()::text,
    'RESERVADO',
    coalesce(p_meias[t.pos], false)
  from unnest(p_nomes_participantes) with ordinality as t(nome, pos);

  perform private.processar_virada_lote_esgotamento(p_evento_id);

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id', i.id,
               'codigo', i.codigo,
               'participante_nome', i.participante_nome,
               'meia', i.meia,
               'valor_unitario', i.valor_unitario
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
    'checkout_token', v_checkout_token,
    'evento_id', p_evento_id,
    'lote_id', v_lote.id,
    'quantidade', v_qtd,
    'valor_unitario', v_valor_unitario,
    'valor_ingressos', v_valor_ingressos,
    'quantidade_meia', v_qtd_meia,
    'valor_unitario_meia', v_preco_meia,
    'taxa_servico_unitaria', v_taxa_unitaria,
    'taxa_repassada', v_evento.taxa_repassada,
    'valor_taxa_total', v_valor_taxa,
    'valor_total', v_valor_total,
    'reserva_expira_em', v_reserva_expira_em,
    'status', 'RESERVADO',
    'ingressos', v_ingressos
  );
end;
$function$;

create function public.criar_reserva(
  p_evento_id uuid, p_comprador_nome text, p_comprador_telefone text,
  p_comprador_email text default null, p_nomes_participantes text[] default null,
  p_meias boolean[] default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.criar_reserva(p_evento_id, p_comprador_nome, p_comprador_telefone, p_comprador_email, p_nomes_participantes, p_meias); $$;

revoke all on function private.criar_reserva(uuid, text, text, text, text[], boolean[]) from public;
grant execute on function private.criar_reserva(uuid, text, text, text, text[], boolean[]) to anon, authenticated, service_role;
revoke all on function public.criar_reserva(uuid, text, text, text, text[], boolean[]) from public;
grant execute on function public.criar_reserva(uuid, text, text, text, text[], boolean[]) to anon, authenticated, service_role;

-- 4) CHECKOUT: valor dos ingressos soma inteiras e meias ---------------------------
CREATE OR REPLACE FUNCTION private.obter_checkout_pedido(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_lote public.lotes%rowtype;
  v_pag public.pagamentos%rowtype;
  v_pag_json jsonb;
begin
  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  if v_pedido.lote_id is not null then
    select * into v_lote from public.lotes l where l.id = v_pedido.lote_id;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;

  if found then
    v_pag_json := jsonb_build_object(
      'pagamento_id', v_pag.id,
      'provedor', v_pag.provedor,
      'status', v_pag.status,
      'valor', v_pag.valor,
      'expira_em', v_pag.expira_em,
      'transacao_id', v_pag.transacao_id,
      'cobranca_id', v_pag.cobranca_id,
      'referencia_externa', v_pag.referencia_externa
    );
  else
    v_pag_json := null;
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'quantidade', v_pedido.quantidade,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_ingressos', (select coalesce(sum(i.valor_unitario), 0) from public.ingressos i where i.pedido_id = v_pedido.id),
    'quantidade_meia', (select count(*) from public.ingressos i where i.pedido_id = v_pedido.id and i.meia),
    'taxa_servico_unitaria', v_pedido.taxa_servico_unitaria,
    'taxa_repassada', v_pedido.taxa_repassada,
    'valor_taxa_total', v_pedido.valor_taxa_total,
    'valor_total', v_pedido.valor_total,
    'pedido_status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pagamento', v_pag_json
  );
end;
$function$;

-- 5) INGRESSOS DO COMPRADOR: indicam a meia-entrada (private.obter_ingressos_checkout) ----------
CREATE OR REPLACE FUNCTION private.obter_ingressos_checkout(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  if p_token is null then
    return null;
  end if;

  select * into v_pedido
    from public.pedidos p
   where p.checkout_token = p_token
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_evento
    from public.eventos e
   where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  v_disponivel := v_pedido.status = 'PAGO'
    and exists (
      select 1
        from public.pagamentos pg
       where pg.pedido_id = v_pedido.id
         and pg.status = 'APROVADO'
    );

  if v_disponivel then
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'meia', i.meia,
                 'status', i.status,
                 -- QR utilizavel somente para ingresso apto a entrar.
                 'qr_token',
                   case
                     when i.status in ('VALIDO', 'UTILIZADO') then i.qr_token
                     else null
                   end,
                 'utilizado_em', i.utilizado_em
               ) order by i.codigo
             ),
             '[]'::jsonb
           )
      into v_ingressos
      from public.ingressos i
     where i.pedido_id = v_pedido.id
       and i.status in ('VALIDO', 'UTILIZADO', 'CANCELADO');
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$function$;

-- 5) INGRESSOS DO COMPRADOR: indicam a meia-entrada (private.montar_ingressos_pedido) ----------
CREATE OR REPLACE FUNCTION private.montar_ingressos_pedido(p_pedido_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_org public.organizacoes%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  select * into v_pedido from public.pedidos p where p.id = p_pedido_id;
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

  select * into v_org from public.organizacoes o where o.id = v_evento.organizacao_id;

  v_disponivel := v_pedido.status = 'PAGO'
    and exists (
      select 1 from public.pagamentos pg
       where pg.pedido_id = v_pedido.id and pg.status = 'APROVADO'
    );

  if v_disponivel then
    select coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'ingresso_id', i.id,
                 'codigo', i.codigo,
                 'participante_nome', i.participante_nome,
                 'meia', i.meia,
                 'status', i.status,
                 'qr_token',
                   case when i.status in ('VALIDO', 'UTILIZADO') then i.qr_token else null end,
                 'utilizado_em', i.utilizado_em
               ) order by i.codigo
             ),
             '[]'::jsonb
           )
      into v_ingressos
      from public.ingressos i
     where i.pedido_id = v_pedido.id
       and i.status in ('VALIDO', 'UTILIZADO', 'CANCELADO');
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'evento_id', v_pedido.evento_id,
    'evento_slug', v_evento.slug,
    'organizacao_slug', v_org.slug,
    'organizacao_nome', v_org.nome,
    'organizacao_logo_url', v_org.logo_url,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$function$;

-- 6) PORTARIA: o resultado informa se o ingresso e meia-entrada -------------------
create or replace function private.anexar_meia_entrada(p_resultado jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select p_resultado || jsonb_build_object(
    'meia',
    coalesce((
      select i.meia from public.ingressos i
       where i.id = nullif(p_resultado->>'ingresso_id', '')::uuid
    ), false)
  );
$$;

revoke all on function private.anexar_meia_entrada(jsonb) from public, anon;
grant execute on function private.anexar_meia_entrada(jsonb) to authenticated, service_role;

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

  return private.anexar_meia_entrada(
    private.processar_entrada(p_evento_id, v_ingresso.id, v_usuario_id, 'QR_CODE')
  );
end;
$function$;

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

  return private.anexar_meia_entrada(
    private.processar_entrada(p_evento_id, p_ingresso_id, v_usuario_id, 'NOME')
  );
end;
$function$;

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
                 'meia', i.meia,
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

-- 7) ADMIN: ligar/desligar a meia-entrada do evento -------------------------------
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
           'publicado_em', e.publicado_em,
           'taxa_repassada', e.taxa_repassada,
           'meia_entrada_ativa', e.meia_entrada_ativa,
           'taxa_servico', (select o.taxa_servico from public.organizacoes o where o.id = e.organizacao_id)
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

create or replace function private.definir_meia_entrada_evento_admin(p_evento_id uuid, p_ativa boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  if not private.evento_da_organizacao_atual(p_evento_id) then
    raise exception 'Evento % nao encontrado', p_evento_id using errcode = '23503';
  end if;
  if p_ativa is null then
    raise exception 'Informe se a meia-entrada esta ativa' using errcode = '23514';
  end if;

  update public.eventos set meia_entrada_ativa = p_ativa where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (auth.uid(), 'EVENTO_MEIA_ENTRADA_DEFINIDA', 'eventos', p_evento_id,
          jsonb_build_object('meia_entrada_ativa', p_ativa));

  return jsonb_build_object('evento_id', p_evento_id, 'meia_entrada_ativa', p_ativa);
end;
$$;

create or replace function public.definir_meia_entrada_evento_admin(p_evento_id uuid, p_ativa boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_meia_entrada_evento_admin(p_evento_id, p_ativa); $$;

revoke all on function private.definir_meia_entrada_evento_admin(uuid, boolean) from public, anon;
grant execute on function private.definir_meia_entrada_evento_admin(uuid, boolean) to authenticated, service_role;
revoke all on function public.definir_meia_entrada_evento_admin(uuid, boolean) from public, anon;
grant execute on function public.definir_meia_entrada_evento_admin(uuid, boolean) to authenticated, service_role;

-- 8) PAGINA PUBLICA: informa se o evento tem meia-entrada --------------------------
drop function public.obter_evento_publico_organizacao(text, text);
drop function private.obter_evento_publico_organizacao(text, text);

CREATE FUNCTION private.obter_evento_publico_organizacao(p_org_slug text, p_evento_slug text)
 RETURNS TABLE(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status status_evento, vendas_status status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text, taxa_servico numeric, taxa_repassada boolean, organizacao_slug text, organizacao_nome text, organizacao_logo_url text, meia_entrada_ativa boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    e.id, e.slug, e.nome, e.descricao, e.imagem_url, e.inicio_em, e.local, e.endereco,
    e.status, e.vendas_status,
    l.id, l.nome, l.preco,
    private.calcular_situacao_venda(e.id),
    case when e.taxa_repassada then o.taxa_servico else 0 end,
    e.taxa_repassada,
    o.slug, o.nome, o.logo_url,
    e.meia_entrada_ativa
  from public.eventos e
  join public.organizacoes o on o.id = e.organizacao_id
  left join lateral (
    select lo.id, lo.nome, lo.preco
      from public.lotes lo
     where lo.evento_id = e.id and lo.status = 'ATIVO'
     limit 1
  ) l on true
  where o.slug = lower(btrim(coalesce(p_org_slug, '')))
    and o.ativo
     and o.aprovada
    and e.slug = lower(btrim(coalesce(p_evento_slug, '')))
    and e.publicacao_status = 'PUBLICADO'
  limit 1;
$function$;

create function public.obter_evento_publico_organizacao(p_org_slug text, p_evento_slug text)
returns table(evento_id uuid, slug text, nome text, descricao text, imagem_url text, inicio_em timestamp with time zone, local text, endereco text, status public.status_evento, vendas_status public.status_vendas, lote_id uuid, lote_nome text, preco numeric, situacao_venda text, taxa_servico numeric, taxa_repassada boolean,
              organizacao_slug text, organizacao_nome text, organizacao_logo_url text, meia_entrada_ativa boolean)
language sql stable security invoker set search_path = ''
as $$ select * from private.obter_evento_publico_organizacao(p_org_slug, p_evento_slug); $$;

revoke all on function private.obter_evento_publico_organizacao(text, text) from public;
grant execute on function private.obter_evento_publico_organizacao(text, text) to anon, authenticated, service_role;
revoke all on function public.obter_evento_publico_organizacao(text, text) from public;
grant execute on function public.obter_evento_publico_organizacao(text, text) to anon, authenticated, service_role;

-- 9) PAINEL: pedido e ingressos mostram a meia-entrada -----------------------------
CREATE OR REPLACE FUNCTION private.obter_pedido_admin(p_pedido_id uuid)
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
               'meia', i.meia,
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

CREATE OR REPLACE FUNCTION private.obter_ingresso_admin(p_ingresso_id uuid)
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
    'meia', v_ing.meia,
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

CREATE OR REPLACE FUNCTION private.listar_ingressos_admin(p_evento_id uuid DEFAULT NULL::uuid, p_pedido_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_status status_ingresso DEFAULT NULL::status_ingresso)
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
               'meia', i.meia,
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
