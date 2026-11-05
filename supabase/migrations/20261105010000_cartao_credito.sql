-- =============================================================================
-- Migration: cartao_credito
--
-- Pagamento com cartao de credito pelo Mercado Pago (mesma API /v1/payments do
-- Pix, com application_fee para a plataforma):
--  * organizacoes.cartao_ativo (padrao false), ligado pelo super admin em
--    Plataforma > Organizacoes (definir_cartao_organizacao);
--  * pagamentos.forma_pagamento (PIX/CARTAO), parcelas, bandeira e final do
--    cartao, preenchidos sozinhos quando o pagamento e aprovado (trigger);
--  * pagamentos_cartao_tentativas: cada tentativa de cartao (no maximo 5 por
--    pedido), para ter chave de idempotencia propria e historico de recusas;
--  * estornar_pedido_externo: estorno ou contestacao (chargeback) feitos fora
--    do painel cancelam o pedido e os ingressos ainda nao usados;
--  * obter_checkout_pagamento_backend devolve o que o servidor precisa para o
--    cartao (public_key da casa, se o cartao esta ligado, dados do comprador).
-- =============================================================================

-- 1) COLUNAS -------------------------------------------------------------------
alter table public.organizacoes
  add column cartao_ativo boolean not null default false;

alter table public.pagamentos
  add column forma_pagamento text null,
  add column parcelas smallint null,
  add column cartao_bandeira text null,
  add column cartao_final text null,
  add constraint ck_pagamentos_forma_pagamento check (forma_pagamento is null or forma_pagamento in ('PIX', 'CARTAO')),
  add constraint ck_pagamentos_parcelas check (parcelas is null or parcelas between 1 and 12);

-- Pagamentos online ja aprovados foram todos via Pix.
update public.pagamentos
   set forma_pagamento = 'PIX'
 where provedor = 'MERCADO_PAGO' and status in ('APROVADO', 'REEMBOLSADO') and forma_pagamento is null;

-- 2) TENTATIVAS DE CARTAO ----------------------------------------------------------
create table public.pagamentos_cartao_tentativas (
  id uuid primary key default gen_random_uuid(),
  pagamento_id uuid not null
    constraint fk_cartao_tentativas_pagamento references public.pagamentos (id) on delete cascade,
  organizacao_id uuid not null
    constraint fk_cartao_tentativas_organizacao references public.organizacoes (id) on delete cascade,
  numero smallint not null,
  mp_payment_id text null,
  status text not null default 'INICIADA',
  status_detail text null,
  parcelas smallint null,
  bandeira text null,
  final text null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint uq_cartao_tentativas_numero unique (pagamento_id, numero),
  constraint ck_cartao_tentativas_status check (status in ('INICIADA', 'APROVADA', 'RECUSADA', 'PENDENTE', 'ERRO'))
);

create unique index uq_cartao_tentativas_mp on public.pagamentos_cartao_tentativas (mp_payment_id)
  where mp_payment_id is not null;

alter table public.pagamentos_cartao_tentativas enable row level security;
revoke all on table public.pagamentos_cartao_tentativas from public, anon, authenticated;
grant select, insert, update, delete on table public.pagamentos_cartao_tentativas to service_role;

-- 3) FORMA DE PAGAMENTO PREENCHIDA NA APROVACAO ------------------------------------
-- Vale para todos os caminhos que confirmam (webhook, pagina, portaria, cron):
-- se a transacao aprovada e uma tentativa de cartao, o pagamento e CARTAO.
create or replace function private.preencher_forma_pagamento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tent public.pagamentos_cartao_tentativas%rowtype;
begin
  if new.provedor <> 'MERCADO_PAGO' then
    return new;
  end if;
  if new.status = 'APROVADO' and old.status is distinct from 'APROVADO' then
    select * into v_tent from public.pagamentos_cartao_tentativas t
     where t.pagamento_id = new.id and t.mp_payment_id = new.transacao_id
     limit 1;
    if found then
      new.forma_pagamento := 'CARTAO';
      new.parcelas := v_tent.parcelas;
      new.cartao_bandeira := v_tent.bandeira;
      new.cartao_final := v_tent.final;
    else
      new.forma_pagamento := coalesce(new.forma_pagamento, 'PIX');
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.preencher_forma_pagamento() from public, anon, authenticated;

create trigger trg_pagamentos_forma_pagamento
  before update of status on public.pagamentos
  for each row execute function private.preencher_forma_pagamento();

-- 4) INICIAR TENTATIVA DE CARTAO (service_role) ------------------------------------
create or replace function private.iniciar_tentativa_cartao(p_token uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
  v_ativo boolean;
  v_numero smallint;
  v_id uuid;
begin
  select * into v_pedido from public.pedidos p where p.checkout_token = p_token;
  if not found then
    raise exception 'Checkout nao encontrado' using errcode = '23503';
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id for update;
  if not found then
    raise exception 'Pagamento nao iniciado' using errcode = '23503';
  end if;
  if v_pag.status = 'APROVADO' then
    return jsonb_build_object('resultado', 'ja_aprovado', 'pagamento_id', v_pag.id);
  end if;
  if v_pag.provedor <> 'MERCADO_PAGO' or v_pag.status <> 'PENDENTE' then
    raise exception 'Pagamento nao esta disponivel para cartao' using errcode = '23514';
  end if;
  if v_pedido.status <> 'RESERVADO' or now() >= v_pedido.reserva_expira_em then
    raise exception 'Reserva expirada' using errcode = '23514';
  end if;

  select o.cartao_ativo into v_ativo from public.organizacoes o where o.id = v_pedido.organizacao_id;
  if not coalesce(v_ativo, false) then
    raise exception 'Cartao nao liberado para esta organizacao' using errcode = '42501';
  end if;

  select coalesce(max(t.numero), 0) + 1 into v_numero
    from public.pagamentos_cartao_tentativas t where t.pagamento_id = v_pag.id;
  if v_numero > 5 then
    raise exception 'Limite de tentativas de cartao atingido' using errcode = '23514';
  end if;

  insert into public.pagamentos_cartao_tentativas (pagamento_id, organizacao_id, numero)
  values (v_pag.id, v_pedido.organizacao_id, v_numero)
  returning id into v_id;

  return jsonb_build_object('resultado', 'iniciada', 'tentativa_id', v_id, 'numero', v_numero,
                            'pagamento_id', v_pag.id);
end;
$$;

create or replace function public.iniciar_tentativa_cartao(p_token uuid)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.iniciar_tentativa_cartao(p_token); $$;

revoke all on function private.iniciar_tentativa_cartao(uuid) from public, anon, authenticated;
grant execute on function private.iniciar_tentativa_cartao(uuid) to service_role;
revoke all on function public.iniciar_tentativa_cartao(uuid) from public, anon, authenticated;
grant execute on function public.iniciar_tentativa_cartao(uuid) to service_role;

-- 5) RESULTADO DA TENTATIVA (service_role) -----------------------------------------
create or replace function private.registrar_tentativa_cartao(
  p_tentativa_id uuid,
  p_mp_payment_id text,
  p_status text,
  p_status_detail text default null,
  p_parcelas smallint default null,
  p_bandeira text default null,
  p_final text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.pagamentos_cartao_tentativas
     set mp_payment_id = coalesce(nullif(btrim(coalesce(p_mp_payment_id, '')), ''), mp_payment_id),
         status = p_status,
         status_detail = left(p_status_detail, 120),
         parcelas = coalesce(p_parcelas, parcelas),
         bandeira = coalesce(left(p_bandeira, 30), bandeira),
         final = coalesce(left(p_final, 4), final),
         atualizado_em = now()
   where id = p_tentativa_id;
  if not found then
    raise exception 'Tentativa % nao encontrada', p_tentativa_id using errcode = '23503';
  end if;
  return jsonb_build_object('tentativa_id', p_tentativa_id, 'status', p_status);
end;
$$;

create or replace function public.registrar_tentativa_cartao(
  p_tentativa_id uuid, p_mp_payment_id text, p_status text, p_status_detail text default null,
  p_parcelas smallint default null, p_bandeira text default null, p_final text default null
)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.registrar_tentativa_cartao(p_tentativa_id, p_mp_payment_id, p_status, p_status_detail,
                                                p_parcelas, p_bandeira, p_final); $$;

revoke all on function private.registrar_tentativa_cartao(uuid, text, text, text, smallint, text, text) from public, anon, authenticated;
grant execute on function private.registrar_tentativa_cartao(uuid, text, text, text, smallint, text, text) to service_role;
revoke all on function public.registrar_tentativa_cartao(uuid, text, text, text, smallint, text, text) from public, anon, authenticated;
grant execute on function public.registrar_tentativa_cartao(uuid, text, text, text, smallint, text, text) to service_role;

-- 6) ESTORNO OU CONTESTACAO FEITOS FORA DO PAINEL (service_role) --------------------
-- Chamado pelo webhook quando a transacao aprovada do pedido vira refunded ou
-- charged_back. Nao age se houver reembolso pelo painel em andamento (ele
-- conclui sozinho) nem se a transacao nao for a que aprovou o pedido.
create or replace function private.estornar_pedido_externo(
  p_pagamento_id uuid,
  p_transacao_id text,
  p_tipo text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pag public.pagamentos%rowtype;
  v_pedido public.pedidos%rowtype;
  v_ts timestamptz := now();
  v_cancelados integer := 0;
  v_utilizados integer := 0;
begin
  if p_tipo not in ('REEMBOLSO', 'CONTESTACAO') then
    raise exception 'Tipo invalido: %', p_tipo using errcode = '22023';
  end if;

  select * into v_pag from public.pagamentos pg where pg.id = p_pagamento_id for update;
  if not found then
    return jsonb_build_object('resultado', 'ignorado', 'motivo', 'pagamento_nao_encontrado');
  end if;
  if v_pag.status <> 'APROVADO' or v_pag.transacao_id is distinct from p_transacao_id then
    return jsonb_build_object('resultado', 'ignorado', 'motivo', 'nao_e_a_transacao_aprovada');
  end if;

  select * into v_pedido from public.pedidos p where p.id = v_pag.pedido_id for update;

  if exists (select 1 from public.cancelamentos_reembolsos c
              where c.pedido_id = v_pedido.id and c.status = 'PENDENTE') then
    return jsonb_build_object('resultado', 'ignorado', 'motivo', 'reembolso_em_andamento');
  end if;

  if p_tipo = 'REEMBOLSO' then
    update public.pagamentos
       set status = 'REEMBOLSADO', valor_reembolsado = valor, reembolsado_em = v_ts
     where id = v_pag.id;
  else
    update public.pagamentos
       set status = 'CANCELADO', cancelado_em = v_ts
     where id = v_pag.id;
  end if;

  update public.pedidos set status = 'CANCELADO', cancelado_em = v_ts where id = v_pedido.id;

  select count(*) into v_utilizados
    from public.ingressos i where i.pedido_id = v_pedido.id and i.status = 'UTILIZADO';

  update public.ingressos
     set status = 'CANCELADO'
   where pedido_id = v_pedido.id and status in ('VALIDO', 'RESERVADO');
  get diagnostics v_cancelados = row_count;

  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, organizacao_id)
  values (null,
          case when p_tipo = 'REEMBOLSO' then 'REEMBOLSO_EXTERNO' else 'CONTESTACAO_RECEBIDA' end,
          'pedidos', v_pedido.id,
          jsonb_build_object('pedido_status', v_pedido.status, 'pagamento_status', v_pag.status),
          jsonb_build_object('transacao_id', p_transacao_id, 'forma_pagamento', v_pag.forma_pagamento,
                             'valor', v_pag.valor, 'ingressos_cancelados', v_cancelados,
                             'ingressos_utilizados', v_utilizados),
          v_pedido.organizacao_id);

  return jsonb_build_object('resultado', 'cancelado', 'pedido_id', v_pedido.id, 'codigo_pedido', v_pedido.codigo,
                            'organizacao_id', v_pedido.organizacao_id, 'valor', v_pag.valor,
                            'ingressos_cancelados', v_cancelados, 'ingressos_utilizados', v_utilizados);
end;
$$;

create or replace function public.estornar_pedido_externo(p_pagamento_id uuid, p_transacao_id text, p_tipo text)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.estornar_pedido_externo(p_pagamento_id, p_transacao_id, p_tipo); $$;

revoke all on function private.estornar_pedido_externo(uuid, text, text) from public, anon, authenticated;
grant execute on function private.estornar_pedido_externo(uuid, text, text) to service_role;
revoke all on function public.estornar_pedido_externo(uuid, text, text) from public, anon, authenticated;
grant execute on function public.estornar_pedido_externo(uuid, text, text) to service_role;

-- 7) SUPER ADMIN LIGA/DESLIGA O CARTAO DE UMA ORGANIZACAO ---------------------------
create or replace function private.definir_cartao_organizacao(p_organizacao_id uuid, p_ativo boolean)
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
  update public.organizacoes set cartao_ativo = coalesce(p_ativo, false) where id = p_organizacao_id;
  if not found then
    raise exception 'Organizacao % nao encontrada', p_organizacao_id using errcode = '23503';
  end if;
  insert into public.auditoria (usuario_id, acao, entidade, entidade_id, dados_novos, organizacao_id)
  values (auth.uid(),
          case when coalesce(p_ativo, false) then 'CARTAO_LIBERADO' else 'CARTAO_BLOQUEADO' end,
          'organizacoes', p_organizacao_id, jsonb_build_object('cartao_ativo', coalesce(p_ativo, false)), p_organizacao_id);
  return jsonb_build_object('organizacao_id', p_organizacao_id, 'cartao_ativo', coalesce(p_ativo, false));
end;
$$;

create or replace function public.definir_cartao_organizacao(p_organizacao_id uuid, p_ativo boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $$ select private.definir_cartao_organizacao(p_organizacao_id, p_ativo); $$;

revoke all on function private.definir_cartao_organizacao(uuid, boolean) from public, anon;
grant execute on function private.definir_cartao_organizacao(uuid, boolean) to authenticated, service_role;
revoke all on function public.definir_cartao_organizacao(uuid, boolean) from public, anon;
grant execute on function public.definir_cartao_organizacao(uuid, boolean) to authenticated, service_role;

-- 8) LISTA DE CASAS DA PLATAFORMA DEVOLVE cartao_ativo ------------------------------
create or replace function private.listar_organizacoes_plataforma()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_e_super_admin() then
    raise exception 'Permissao negada: apenas super administrador' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'organizacao_id', o.id,
             'nome', o.nome,
             'slug', o.slug,
             'ativo', o.ativo,
             'aprovada', o.aprovada,
             'lista_vip_ativa', o.lista_vip_ativa,
             'cartao_ativo', o.cartao_ativo,
             'taxa_servico', o.taxa_servico,
             'criado_em', o.criado_em,
             'mercado_pago_conectado', exists (
               select 1 from public.organizacoes_mercado_pago mp where mp.organizacao_id = o.id),
             'administradores', coalesce((
               select string_agg(u.email, ', ' order by u.email)
                 from public.membros_organizacao m
                 join public.usuarios u on u.id = m.usuario_id
                where m.organizacao_id = o.id and m.ativo and m.perfil = 'ADMINISTRADOR'), ''),
             'eventos', (select count(*) from public.eventos e where e.organizacao_id = o.id)
           ) order by o.aprovada, o.criado_em desc)
      from public.organizacoes o
  ), '[]'::jsonb);
end;
$$;

-- 9) CHECKOUT DO BACKEND: DADOS PARA O CARTAO ---------------------------------------
CREATE OR REPLACE FUNCTION private.obter_checkout_pagamento_backend(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pedido public.pedidos%rowtype;
  v_pag public.pagamentos%rowtype;
  v_evento_nome text;
  v_cartao_ativo boolean;
  v_public_key text;
  v_tentativas integer := 0;
begin
  select * into v_pedido from public.pedidos p where p.checkout_token = p_token limit 1;
  if not found then
    return null;
  end if;

  select * into v_pag from public.pagamentos pg where pg.pedido_id = v_pedido.id limit 1;
  select e.nome into v_evento_nome from public.eventos e where e.id = v_pedido.evento_id;
  select o.cartao_ativo into v_cartao_ativo from public.organizacoes o where o.id = v_pedido.organizacao_id;
  select mp.public_key into v_public_key
    from public.organizacoes_mercado_pago mp where mp.organizacao_id = v_pedido.organizacao_id;
  if v_pag.id is not null then
    select count(*) into v_tentativas from public.pagamentos_cartao_tentativas t where t.pagamento_id = v_pag.id;
  end if;

  return jsonb_build_object(
    'pedido_id', v_pedido.id,
    'codigo_pedido', v_pedido.codigo,
    'comprador_email', v_pedido.comprador_email,
    'comprador_nome', v_pedido.comprador_nome,
    'comprador_telefone', v_pedido.comprador_telefone,
    'evento_nome', v_evento_nome,
    'quantidade', v_pedido.quantidade,
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
    'expira_em', v_pag.expira_em,
    'forma_pagamento', v_pag.forma_pagamento,
    'cartao_ativo', coalesce(v_cartao_ativo, false),
    'mp_public_key', v_public_key,
    'tentativas_cartao', v_tentativas
  );
end;
$function$;

-- 10) NOVOS TIPOS DE ALERTA ----------------------------------------------------------
alter table public.erros_pagamento drop constraint ck_erros_pagamento_tipo;
alter table public.erros_pagamento add constraint ck_erros_pagamento_tipo check (tipo in (
  'PIX_CRIACAO', 'CONTA_MP_DESCONECTADA', 'TOKEN_MP', 'OAUTH_MP', 'WEBHOOK',
  'CONFIRMACAO', 'VALOR_DIVERGENTE', 'REEMBOLSO', 'CONFIGURACAO',
  'CARTAO', 'CONTESTACAO', 'PAGAMENTO_DUPLICADO'
));
