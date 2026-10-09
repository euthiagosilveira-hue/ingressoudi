-- =============================================================================
-- GZ1 Ingresso - Compartilhamento seguro de UM ingresso individual
-- Migration: compartilhamento_ingresso
--
-- Fluxo:
--   * criar_compartilhamento_ingresso(checkout_token | recovery_token, ingresso)
--       valida acesso ao pedido (PAGO + pagamento APROVADO), confere que o
--       ingresso pertence ao pedido e esta VALIDO, revoga shares ativos
--       anteriores e gera novo bearer token (256 bits, so hash md5 no banco).
--   * obter_compartilhamento_ingresso(token) -> dados publicos (SEM qr_token)
--   * obter_qr_compartilhamento(token)        -> qr_token (SO service_role)
--
-- O qr_token NUNCA e devolvido ao browser: o endpoint de QR gera a imagem
-- server-side. Portaria continua usando registrar_entrada_qr(evento_id, qr_token).
-- =============================================================================

create table if not exists public.compartilhamentos_ingresso (
  id uuid primary key default gen_random_uuid(),
  ingresso_id uuid not null
    constraint fk_compartilhamentos_ingresso references public.ingressos (id) on delete restrict,
  token_hash text not null
    constraint uq_compartilhamentos_token_hash unique,
  ativo boolean not null default true,
  expira_em timestamptz null,
  criado_em timestamptz not null default now(),
  revogado_em timestamptz null,
  ultimo_acesso_em timestamptz null
);

create index if not exists idx_compartilhamentos_ingresso
  on public.compartilhamentos_ingresso (ingresso_id);

alter table public.compartilhamentos_ingresso enable row level security;
revoke all privileges on table public.compartilhamentos_ingresso from anon, authenticated;

-- 1) CRIAR (valida acesso + estado + idempotencia por revogacao) --------------
create or replace function private.criar_compartilhamento_ingresso(
  p_checkout_token uuid,
  p_recovery_token text,
  p_ingresso_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_ingresso public.ingressos%rowtype;
  v_token text;
begin
  if p_ingresso_id is null then
    return jsonb_build_object('ok', false);
  end if;

  -- resolve o pedido pelo acesso informado (checkout OU recuperacao)
  if p_checkout_token is not null then
    select * into v_pedido from public.pedidos p where p.checkout_token = p_checkout_token limit 1;
  elsif p_recovery_token is not null and btrim(p_recovery_token) <> '' then
    select p.* into v_pedido
      from public.recuperacoes_ingressos r
      join public.pedidos p on p.id = r.pedido_id
     where r.token_hash = md5(btrim(p_recovery_token))
       and r.expira_em > now()
     order by r.criado_em desc
     limit 1;
  end if;

  if v_pedido.id is null then
    return jsonb_build_object('ok', false);
  end if;

  if v_pedido.status <> 'PAGO'
     or not exists (
       select 1 from public.pagamentos pg
        where pg.pedido_id = v_pedido.id and pg.status = 'APROVADO'
     )
  then
    return jsonb_build_object('ok', false);
  end if;

  select * into v_ingresso
    from public.ingressos i
   where i.id = p_ingresso_id and i.pedido_id = v_pedido.id;

  if not found or v_ingresso.status <> 'VALIDO' then
    return jsonb_build_object('ok', false);
  end if;

  -- idempotencia: revoga shares ativos anteriores deste ingresso
  update public.compartilhamentos_ingresso
     set ativo = false, revogado_em = now()
   where ingresso_id = v_ingresso.id and ativo = true and revogado_em is null;

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  insert into public.compartilhamentos_ingresso (ingresso_id, token_hash)
  values (v_ingresso.id, md5(v_token));

  return jsonb_build_object('ok', true, 'token', v_token);
end;
$$;

-- 2) RESOLVER (publico, SEM qr_token) -----------------------------------------
create or replace function private.obter_compartilhamento_ingresso(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_share public.compartilhamentos_ingresso%rowtype;
  v_ing public.ingressos%rowtype;
  v_evento public.eventos%rowtype;
  v_entrada_em timestamptz;
begin
  if p_token is null or btrim(p_token) = '' then
    return null;
  end if;

  select * into v_share
    from public.compartilhamentos_ingresso c
   where c.token_hash = md5(btrim(p_token))
     and c.ativo = true
     and c.revogado_em is null
     and (c.expira_em is null or c.expira_em > now())
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_ing from public.ingressos i where i.id = v_share.ingresso_id;
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_ing.evento_id;

  select en.entrada_em into v_entrada_em
    from public.entradas en
   where en.ingresso_id = v_ing.id and en.anulada_em is null
   order by en.entrada_em desc
   limit 1;

  update public.compartilhamentos_ingresso
     set ultimo_acesso_em = now()
   where id = v_share.id;

  return jsonb_build_object(
    'ingresso_id', v_ing.id,
    'codigo', v_ing.codigo,
    'participante_nome', v_ing.participante_nome,
    'status', v_ing.status,
    'utilizado_em', v_ing.utilizado_em,
    'entrada_em', v_entrada_em,
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco
  );
end;
$$;

-- 3) QR TOKEN (SO service_role; usado pelo endpoint server-side) --------------
create or replace function private.obter_qr_compartilhamento(p_token text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_share public.compartilhamentos_ingresso%rowtype;
  v_ing public.ingressos%rowtype;
begin
  if p_token is null or btrim(p_token) = '' then
    return null;
  end if;

  select * into v_share
    from public.compartilhamentos_ingresso c
   where c.token_hash = md5(btrim(p_token))
     and c.ativo = true
     and c.revogado_em is null
     and (c.expira_em is null or c.expira_em > now())
   limit 1;

  if not found then
    return null;
  end if;

  select * into v_ing from public.ingressos i where i.id = v_share.ingresso_id;
  if not found or v_ing.status <> 'VALIDO' then
    return null;
  end if;

  return v_ing.qr_token;
end;
$$;

-- 4) WRAPPERS PUBLICOS --------------------------------------------------------
create or replace function public.criar_compartilhamento_ingresso(
  p_checkout_token uuid,
  p_recovery_token text,
  p_ingresso_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.criar_compartilhamento_ingresso(p_checkout_token, p_recovery_token, p_ingresso_id);
$$;

create or replace function public.obter_compartilhamento_ingresso(p_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_compartilhamento_ingresso(p_token);
$$;

create or replace function public.obter_qr_compartilhamento(p_token text)
returns text
language sql
security invoker
set search_path = ''
as $$
  select private.obter_qr_compartilhamento(p_token);
$$;

-- 5) ACL ----------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;

revoke all on function private.criar_compartilhamento_ingresso(uuid, text, uuid) from public;
grant execute on function private.criar_compartilhamento_ingresso(uuid, text, uuid) to service_role;

revoke all on function private.obter_compartilhamento_ingresso(text) from public;
grant execute on function private.obter_compartilhamento_ingresso(text) to anon, authenticated, service_role;

revoke all on function private.obter_qr_compartilhamento(text) from public;
grant execute on function private.obter_qr_compartilhamento(text) to service_role;

revoke execute on function public.criar_compartilhamento_ingresso(uuid, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.criar_compartilhamento_ingresso(uuid, text, uuid) to service_role;

revoke execute on function public.obter_compartilhamento_ingresso(text)
  from public, anon, authenticated, service_role;
grant execute on function public.obter_compartilhamento_ingresso(text) to anon, authenticated, service_role;

-- QR token: NUNCA acessivel por anon/authenticated
revoke execute on function public.obter_qr_compartilhamento(text)
  from public, anon, authenticated, service_role;
grant execute on function public.obter_qr_compartilhamento(text) to service_role;

comment on function public.criar_compartilhamento_ingresso(uuid, text, uuid) is
  'Cria/renova link de compartilhamento de um ingresso. Apenas backend (service_role).';
comment on function public.obter_compartilhamento_ingresso(text) is
  'Dados publicos do ingresso compartilhado (sem qr_token, sem dados do comprador).';
comment on function public.obter_qr_compartilhamento(text) is
  'Retorna o qr_token real apenas para o endpoint server-side gerar o QR.';
