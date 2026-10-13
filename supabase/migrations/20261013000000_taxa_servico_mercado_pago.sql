-- =============================================================================
-- Ingressoudi - Fase 2A: taxa de servico da plataforma e conexao Mercado Pago
-- Migration: taxa_servico_mercado_pago
--
-- * organizacoes.taxa_servico: valor fixo por ingresso (padrao R$ 1,00),
--   ajustavel por organizacao pelo super admin.
-- * eventos.taxa_repassada: o produtor decide por evento se o comprador paga
--   a taxa (ingresso + taxa) ou se ela sai do valor do produtor.
-- * pedidos guardam a taxa aplicada (historico, como o preco).
--   pedidos.valor_total = valor COBRADO do comprador.
--   pedidos.valor_taxa_total = comissao da plataforma (application_fee).
-- * organizacoes_mercado_pago: conta Mercado Pago conectada (OAuth) por
--   organizacao. Tokens CIFRADOS pela aplicacao; tabela so para service_role.
-- * Venda manual (dinheiro) nao cobra taxa: nao passa pelo Mercado Pago.
-- =============================================================================

-- 1) COLUNAS -----------------------------------------------------------------------
alter table public.organizacoes
  add column taxa_servico numeric(10,2) not null default 1.00,
  add constraint ck_organizacoes_taxa_servico check (taxa_servico >= 0 and taxa_servico <= 100);

alter table public.eventos
  add column taxa_repassada boolean not null default true;

alter table public.pedidos
  add column taxa_servico_unitaria numeric(10,2) not null default 0,
  add column taxa_repassada boolean not null default true,
  add column valor_taxa_total numeric(10,2) not null default 0,
  add constraint ck_pedidos_taxa check (
    taxa_servico_unitaria >= 0 and valor_taxa_total >= 0 and valor_taxa_total <= valor_total
  );

-- 2) CONEXAO MERCADO PAGO POR ORGANIZACAO ------------------------------------------
create table public.organizacoes_mercado_pago (
  organizacao_id uuid primary key,
  mp_user_id text not null,
  access_token_cifrado text not null,
  refresh_token_cifrado text,
  public_key text,
  live_mode boolean not null default false,
  expira_em timestamptz,
  conectado_por_usuario_id uuid,
  conectado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint fk_org_mp_organizacao foreign key (organizacao_id)
    references public.organizacoes (id) on delete cascade,
  constraint fk_org_mp_usuario foreign key (conectado_por_usuario_id)
    references public.usuarios (id) on delete set null
);

create index idx_org_mp_user on public.organizacoes_mercado_pago (mp_user_id);

create trigger trg_organizacoes_mercado_pago_atualizado_em
  before update on public.organizacoes_mercado_pago
  for each row execute function public.definir_atualizado_em();

alter table public.organizacoes_mercado_pago enable row level security;
revoke all privileges on table public.organizacoes_mercado_pago from anon, authenticated;


-- 3) criar_reserva: aplica a taxa de servico
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

  v_codigo := 'GZ' || nextval('public.seq_pedido_codigo')::text;
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

-- 4) obter_checkout_pedido: expoe a composicao do valor
CREATE OR REPLACE FUNCTION private.obter_checkout_pedido(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
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
    'evento_nome', v_evento.nome,
    'lote_id', v_pedido.lote_id,
    'lote_nome', v_lote.nome,
    'quantidade', v_pedido.quantidade,
    'valor_unitario', v_pedido.valor_unitario,
    'valor_ingressos', v_pedido.valor_unitario * v_pedido.quantidade,
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

-- 5) obter_checkout_pagamento_backend: comissao e organizacao para o backend (service_role)
CREATE OR REPLACE FUNCTION private.obter_checkout_pagamento_backend(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
begin
  select * into v_pedido from public.pedidos p where p.checkout_token = p_token limit 1;
  if not found then
    return null;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'comprador_email', v_pedido.comprador_email,
    'valor_total', v_pedido.valor_total,
    'valor_taxa_total', v_pedido.valor_taxa_total,
    'organizacao_id', v_pedido.organizacao_id,
    'pedido_status', v_pedido.status,
    'reserva_expira_em', v_pedido.reserva_expira_em,
    'pagamento_id', v_pag.id,
    'provedor', v_pag.provedor,
    'pagamento_status', v_pag.status,
    'transacao_id', v_pag.transacao_id,
    'cobranca_id', v_pag.cobranca_id,
    'referencia_externa', v_pag.referencia_externa,
    'pix_copia_cola', v_pag.pix_copia_cola,
    'pix_qr_code', v_pag.pix_qr_code,
    'expira_em', v_pag.expira_em
  );
end;
$function$;

-- 6) obter_evento_admin: taxa do evento
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


-- 7) NOVAS RPCs ------------------------------------------------------------------

-- Admin: define se a taxa do evento e repassada ao comprador ou absorvida.
create or replace function private.definir_taxa_evento_admin(p_evento_id uuid, p_taxa_repassada boolean)
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
  if p_taxa_repassada is null then
    raise exception 'Informe se a taxa e repassada' using errcode = '23514';
  end if;

  update public.eventos set taxa_repassada = p_taxa_repassada where id = p_evento_id;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos)
  values (auth.uid(), 'EVENTO_TAXA_DEFINIDA', 'eventos', p_evento_id,
          jsonb_build_object('taxa_repassada', p_taxa_repassada));

  return jsonb_build_object('evento_id', p_evento_id, 'taxa_repassada', p_taxa_repassada);
end;
$$;

create or replace function public.definir_taxa_evento_admin(p_evento_id uuid, p_taxa_repassada boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_taxa_evento_admin(p_evento_id, p_taxa_repassada); $$;

-- Super admin: define o valor da taxa de uma organizacao.
create or replace function private.definir_taxa_organizacao(p_organizacao_id uuid, p_taxa numeric)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  if p_taxa is null or p_taxa < 0 or p_taxa > 100 then
    raise exception 'Taxa invalida' using errcode = '23514';
  end if;

  update public.organizacoes set taxa_servico = round(p_taxa, 2) where id = p_organizacao_id;
  if not found then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(), 'ORGANIZACAO_TAXA_DEFINIDA', 'organizacoes', p_organizacao_id,
          jsonb_build_object('taxa_servico', round(p_taxa, 2)), p_organizacao_id);

  return jsonb_build_object('organizacao_id', p_organizacao_id, 'taxa_servico', round(p_taxa, 2));
end;
$$;

create or replace function public.definir_taxa_organizacao(p_organizacao_id uuid, p_taxa numeric)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_taxa_organizacao(p_organizacao_id, p_taxa); $$;

-- Admin: status da conexao Mercado Pago da organizacao ativa (sem tokens).
create or replace function private.obter_status_mercado_pago()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
  v_row public.organizacoes_mercado_pago%rowtype;
  v_taxa numeric;
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  select o.taxa_servico into v_taxa from public.organizacoes o where o.id = v_org;
  select * into v_row from public.organizacoes_mercado_pago m where m.organizacao_id = v_org;

  return jsonb_build_object(
    'conectado', found,
    'mp_user_id', v_row.mp_user_id,
    'live_mode', v_row.live_mode,
    'conectado_em', v_row.conectado_em,
    'expira_em', v_row.expira_em,
    'taxa_servico', v_taxa
  );
end;
$$;

create or replace function public.obter_status_mercado_pago()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_status_mercado_pago(); $$;

-- Admin: desconecta a conta Mercado Pago da organizacao ativa.
create or replace function private.desconectar_mercado_pago()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.organizacao_atual_id();
begin
  if not private.usuario_e_admin() then
    raise exception 'Permissao negada: apenas ADMINISTRADOR' using errcode = '42501';
  end if;

  delete from public.organizacoes_mercado_pago where organizacao_id = v_org;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, organizacao_id)
  values (auth.uid(), 'MERCADO_PAGO_DESCONECTADO', 'organizacoes', v_org, v_org);

  return jsonb_build_object('conectado', false);
end;
$$;

create or replace function public.desconectar_mercado_pago()
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.desconectar_mercado_pago(); $$;

-- Publico: taxa exibida na pagina do evento (antes da compra).
create or replace function private.obter_taxa_evento_publico(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'taxa_servico', case when e.taxa_repassada then o.taxa_servico else 0 end,
           'taxa_repassada', e.taxa_repassada
         )
    from public.eventos e
    join public.organizacoes o on o.id = e.organizacao_id
   where e.slug = p_slug
     and e.publicacao_status = 'PUBLICADO'
   limit 1;
$$;

create or replace function public.obter_taxa_evento_publico(p_slug text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select private.obter_taxa_evento_publico(p_slug); $$;

-- 8) PERMISSOES ------------------------------------------------------------------
revoke all on function private.definir_taxa_evento_admin(uuid, boolean) from public, anon;
revoke all on function private.definir_taxa_organizacao(uuid, numeric) from public, anon;
revoke all on function private.obter_status_mercado_pago() from public, anon;
revoke all on function private.desconectar_mercado_pago() from public, anon;
revoke all on function private.obter_taxa_evento_publico(text) from public;
grant execute on function private.definir_taxa_evento_admin(uuid, boolean) to authenticated, service_role;
grant execute on function private.definir_taxa_organizacao(uuid, numeric) to authenticated, service_role;
grant execute on function private.obter_status_mercado_pago() to authenticated, service_role;
grant execute on function private.desconectar_mercado_pago() to authenticated, service_role;
grant execute on function private.obter_taxa_evento_publico(text) to anon, authenticated, service_role;

revoke all on function public.definir_taxa_evento_admin(uuid, boolean) from public, anon;
revoke all on function public.definir_taxa_organizacao(uuid, numeric) from public, anon;
revoke all on function public.obter_status_mercado_pago() from public, anon;
revoke all on function public.desconectar_mercado_pago() from public, anon;
revoke all on function public.obter_taxa_evento_publico(text) from public;
grant execute on function public.definir_taxa_evento_admin(uuid, boolean) to authenticated, service_role;
grant execute on function public.definir_taxa_organizacao(uuid, numeric) to authenticated, service_role;
grant execute on function public.obter_status_mercado_pago() to authenticated, service_role;
grant execute on function public.desconectar_mercado_pago() to authenticated, service_role;
grant execute on function public.obter_taxa_evento_publico(text) to anon, authenticated, service_role;
