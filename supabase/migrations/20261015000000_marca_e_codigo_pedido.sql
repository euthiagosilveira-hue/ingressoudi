-- =============================================================================
-- Ingressoudi - Fase 3B (parte 1): marca da casa e codigo do pedido da plataforma
--  * organizacoes.cor_primaria (cor de destaque da pagina publica)
--  * RPCs da marca: obter_marca_organizacao / atualizar_marca_organizacao (admin)
--  * obter_organizacao_publica passa a devolver cor_primaria
--  * codigo do pedido com prefixo unico da plataforma (IU), centralizado em
--    private.gerar_codigo_pedido(). Pedidos antigos mantem o codigo (GZ...).
-- =============================================================================

-- 1) COR DA CASA ------------------------------------------------------------------
alter table public.organizacoes
  add column cor_primaria text null,
  add constraint ck_organizacoes_cor_primaria check (
    cor_primaria is null or cor_primaria ~ '^#[0-9a-fA-F]{6}$'
  );

-- 2) CODIGO DO PEDIDO ---------------------------------------------------------------
create or replace function private.gerar_codigo_pedido()
returns text
language sql
volatile
set search_path = ''
as $$
  select 'IU' || nextval('public.seq_pedido_codigo')::text;
$$;

revoke all on function private.gerar_codigo_pedido() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.criar_reserva(p_evento_id uuid, p_comprador_nome text, p_comprador_telefone text, p_comprador_email text DEFAULT NULL::text, p_nomes_participantes text[] DEFAULT NULL::text[])
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
  v_valor_ingressos := v_lote.preco * v_qtd;

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
    v_taxa_unitaria := least(v_taxa_unitaria, v_lote.preco);
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

  perform private.processar_virada_lote_esgotamento(p_evento_id);

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
    'checkout_token', v_checkout_token,
    'evento_id', p_evento_id,
    'lote_id', v_lote.id,
    'quantidade', v_qtd,
    'valor_unitario', v_valor_unitario,
    'valor_ingressos', v_valor_ingressos,
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

  v_codigo := private.gerar_codigo_pedido();
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

-- 3) MARCA DA CASA (admin da organizacao ativa) ------------------------------------
create or replace function private.obter_marca_organizacao()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org public.organizacoes%rowtype;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  select * into v_org from public.organizacoes o where o.id = private.organizacao_atual_id();
  if not found then
    raise exception 'Organizacao nao encontrada' using errcode = '23503';
  end if;
  return jsonb_build_object(
    'organizacao_id', v_org.id,
    'nome', v_org.nome,
    'slug', v_org.slug,
    'logo_url', v_org.logo_url,
    'cor_primaria', v_org.cor_primaria
  );
end;
$$;

create or replace function public.obter_marca_organizacao()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_marca_organizacao(); $$;

create or replace function private.atualizar_marca_organizacao(p_logo_url text, p_cor_primaria text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
  v_logo text := nullif(btrim(coalesce(p_logo_url, '')), '');
  v_cor text := nullif(lower(btrim(coalesce(p_cor_primaria, ''))), '');
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;
  if v_org is null then
    raise exception 'Organizacao nao encontrada' using errcode = '23503';
  end if;
  if v_logo is not null and v_logo !~* '^(https://|/)' then
    raise exception 'Logo invalido: use uma imagem enviada pelo painel' using errcode = '23514';
  end if;
  if v_cor is not null and v_cor !~ '^#[0-9a-f]{6}$' then
    raise exception 'Cor invalida: use o formato #RRGGBB' using errcode = '23514';
  end if;

  update public.organizacoes
     set logo_url = v_logo,
         cor_primaria = v_cor
   where id = v_org;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(), 'ORGANIZACAO_MARCA_ATUALIZADA', 'organizacoes', v_org,
          jsonb_build_object('logo_url', v_logo, 'cor_primaria', v_cor), v_org);

  return private.obter_marca_organizacao();
end;
$$;

create or replace function public.atualizar_marca_organizacao(p_logo_url text, p_cor_primaria text)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.atualizar_marca_organizacao(p_logo_url, p_cor_primaria); $$;

-- 4) PAGINA PUBLICA COM A COR DA CASA --------------------------------------------------
create or replace function private.obter_organizacao_publica(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('organizacao_id', o.id, 'nome', o.nome, 'slug', o.slug,
                            'logo_url', o.logo_url, 'cor_primaria', o.cor_primaria)
    from public.organizacoes o
   where o.slug = lower(btrim(coalesce(p_slug, '')))
     and o.ativo
   limit 1;
$$;

-- 5) PERMISSOES ------------------------------------------------------------------
revoke all on function private.obter_marca_organizacao() from public, anon;
revoke all on function private.atualizar_marca_organizacao(text, text) from public, anon;
grant execute on function private.obter_marca_organizacao() to authenticated, service_role;
grant execute on function private.atualizar_marca_organizacao(text, text) to authenticated, service_role;
revoke all on function public.obter_marca_organizacao() from public, anon;
revoke all on function public.atualizar_marca_organizacao(text, text) from public, anon;
grant execute on function public.obter_marca_organizacao() to authenticated, service_role;
grant execute on function public.atualizar_marca_organizacao(text, text) to authenticated, service_role;
