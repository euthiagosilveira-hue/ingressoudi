-- =============================================================================
-- GZ1 Ingresso - Recuperacao de ingressos por codigo do pedido + telefone
-- Migration: recuperacao_ingressos
--
-- Fluxo seguro (NAO devolve checkout_token):
--   codigo + telefone validos -> gera token de recuperacao temporario (bearer)
--   -> browser acessa os ingressos via obter_ingressos_recuperacao(token)
--
--   * public.recuperar_ingressos(codigo, telefone) -> { ok, token, expira_em }
--   * public.obter_ingressos_recuperacao(token)    -> mesmo shape do checkout
--
-- Token: 256 bits (2 UUIDs), guardado apenas como md5(token). Validade 30 min.
-- Rate limit minimo por codigo (janela 15 min). Mensagem sempre generica.
-- Nao altera RLS/ACL existentes. Nao expoe qr_token fora do fluxo autorizado.
-- =============================================================================

-- 1) TABELAS ------------------------------------------------------------------
create table if not exists public.recuperacoes_ingressos (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null
    constraint fk_recuperacoes_pedido references public.pedidos (id) on delete restrict,
  token_hash text not null,
  expira_em timestamptz not null,
  usado_em timestamptz null,
  ultimo_acesso_em timestamptz null,
  criado_em timestamptz not null default now()
);

create index if not exists idx_recuperacoes_token_hash
  on public.recuperacoes_ingressos (token_hash);
create index if not exists idx_recuperacoes_pedido
  on public.recuperacoes_ingressos (pedido_id);

create table if not exists public.tentativas_recuperacao (
  id uuid primary key default gen_random_uuid(),
  codigo_normalizado text not null,
  sucesso boolean not null,
  criado_em timestamptz not null default now()
);

create index if not exists idx_tentativas_recuperacao_codigo
  on public.tentativas_recuperacao (codigo_normalizado, criado_em);

alter table public.recuperacoes_ingressos enable row level security;
alter table public.tentativas_recuperacao enable row level security;
revoke all privileges on table public.recuperacoes_ingressos from anon, authenticated;
revoke all privileges on table public.tentativas_recuperacao from anon, authenticated;

-- 2) BUILDER COMPARTILHADO (mesmo shape de obter_ingressos_checkout) ----------
create or replace function private.montar_ingressos_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_evento public.eventos%rowtype;
  v_disponivel boolean := false;
  v_ingressos jsonb := '[]'::jsonb;
begin
  select * into v_pedido from public.pedidos p where p.id = p_pedido_id;
  if not found then
    return null;
  end if;

  select * into v_evento from public.eventos e where e.id = v_pedido.evento_id;

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
    'evento_nome', v_evento.nome,
    'evento_inicio_em', v_evento.inicio_em,
    'evento_local', v_evento.local,
    'evento_endereco', v_evento.endereco,
    'pedido_status', v_pedido.status,
    'disponivel', v_disponivel,
    'ingressos', v_ingressos
  );
end;
$$;

-- 3) RECUPERAR (codigo + telefone) -------------------------------------------
create or replace function private.recuperar_ingressos(p_codigo text, p_telefone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_codigo text;
  v_digitos text;
  v_pedido public.pedidos%rowtype;
  v_token text;
  v_expira timestamptz;
  v_tentativas integer;
  v_ok boolean := false;
begin
  v_codigo := upper(btrim(coalesce(p_codigo, '')));
  v_digitos := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');

  if v_codigo = '' or v_digitos = '' then
    return jsonb_build_object('ok', false);
  end if;

  -- rate limit minimo por codigo (janela 15 min)
  select count(*) into v_tentativas
    from public.tentativas_recuperacao t
   where t.codigo_normalizado = v_codigo
     and t.sucesso = false
     and t.criado_em > now() - interval '15 minutes';

  if v_tentativas >= 5 then
    insert into public.tentativas_recuperacao (codigo_normalizado, sucesso)
    values (v_codigo, false);
    return jsonb_build_object('ok', false);
  end if;

  select * into v_pedido from public.pedidos p where upper(p.codigo) = v_codigo;

  if found
     and regexp_replace(coalesce(v_pedido.comprador_telefone, ''), '\D', '', 'g') = v_digitos
     and v_pedido.status = 'PAGO'
     and exists (
       select 1 from public.pagamentos pg
        where pg.pedido_id = v_pedido.id and pg.status = 'APROVADO'
     )
  then
    v_ok := true;
  end if;

  insert into public.tentativas_recuperacao (codigo_normalizado, sucesso)
  values (v_codigo, v_ok);

  if not v_ok then
    return jsonb_build_object('ok', false);
  end if;

  -- invalida recuperacoes ativas anteriores do mesmo pedido
  update public.recuperacoes_ingressos
     set expira_em = now()
   where pedido_id = v_pedido.id and usado_em is null and expira_em > now();

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_expira := now() + interval '30 minutes';

  insert into public.recuperacoes_ingressos (pedido_id, token_hash, expira_em)
  values (v_pedido.id, md5(v_token), v_expira);

  return jsonb_build_object('ok', true, 'token', v_token, 'expira_em', v_expira);
end;
$$;

-- 4) OBTER INGRESSOS POR TOKEN DE RECUPERACAO --------------------------------
create or replace function private.obter_ingressos_recuperacao(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec public.recuperacoes_ingressos%rowtype;
begin
  if p_token is null or btrim(p_token) = '' then
    return null;
  end if;

  select * into v_rec
    from public.recuperacoes_ingressos r
   where r.token_hash = md5(btrim(p_token))
     and r.expira_em > now()
   order by r.criado_em desc
   limit 1;

  if not found then
    return null;
  end if;

  update public.recuperacoes_ingressos
     set ultimo_acesso_em = now(),
         usado_em = coalesce(usado_em, now())
   where id = v_rec.id;

  return private.montar_ingressos_pedido(v_rec.pedido_id);
end;
$$;

-- 5) WRAPPERS PUBLICOS --------------------------------------------------------
create or replace function public.recuperar_ingressos(p_codigo text, p_telefone text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.recuperar_ingressos(p_codigo, p_telefone);
$$;

create or replace function public.obter_ingressos_recuperacao(p_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.obter_ingressos_recuperacao(p_token);
$$;

-- 6) ACL ----------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;

revoke all on function private.montar_ingressos_pedido(uuid) from public;
grant execute on function private.montar_ingressos_pedido(uuid) to anon, authenticated, service_role;

revoke all on function private.recuperar_ingressos(text, text) from public;
grant execute on function private.recuperar_ingressos(text, text) to anon, authenticated, service_role;

revoke all on function private.obter_ingressos_recuperacao(text) from public;
grant execute on function private.obter_ingressos_recuperacao(text) to anon, authenticated, service_role;

revoke execute on function public.recuperar_ingressos(text, text) from public, anon, authenticated, service_role;
grant execute on function public.recuperar_ingressos(text, text) to anon, authenticated, service_role;

revoke execute on function public.obter_ingressos_recuperacao(text) from public, anon, authenticated, service_role;
grant execute on function public.obter_ingressos_recuperacao(text) to anon, authenticated, service_role;

comment on function public.recuperar_ingressos(text, text) is
  'Gera token temporario de recuperacao (codigo + telefone). Resposta generica.';
comment on function public.obter_ingressos_recuperacao(text) is
  'Ingressos do pedido via token de recuperacao temporario (bearer, 30 min).';
