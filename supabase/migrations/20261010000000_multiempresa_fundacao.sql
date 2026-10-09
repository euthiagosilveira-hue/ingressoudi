-- =============================================================================
-- Ingressoudi - Multiempresa: fundacao (Etapa A)
-- Migration: multiempresa_fundacao
--
-- Cria organizacoes e membros (perfil POR ORGANIZACAO), organizacao ativa do
-- usuario, super admin da plataforma, organizacao_id nas tabelas operacionais
-- (preenchido e validado por trigger) e redefine o helper de perfil para que
-- usuario_e_admin() / usuario_pode_operar_portaria() passem a considerar a
-- organizacao ativa.
--
-- Banco novo e vazio: as colunas organizacao_id ja nascem NOT NULL.
-- ATENCAO: as RPCs de listagem ainda NAO filtram por organizacao (Etapa B).
-- =============================================================================

-- 1) ORGANIZACOES ---------------------------------------------------------------
create table public.organizacoes (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  slug text not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint uq_organizacoes_slug unique (slug),
  constraint ck_organizacoes_nome check (btrim(nome) <> ''),
  constraint ck_organizacoes_slug check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

create trigger trg_organizacoes_atualizado_em
  before update on public.organizacoes
  for each row execute function public.definir_atualizado_em();

-- 2) MEMBROS DA ORGANIZACAO -------------------------------------------------------
create table public.membros_organizacao (
  organizacao_id uuid not null,
  usuario_id uuid not null,
  perfil public.perfil_usuario not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint pk_membros_organizacao primary key (organizacao_id, usuario_id),
  constraint fk_membros_organizacao_organizacao
    foreign key (organizacao_id) references public.organizacoes (id) on delete restrict,
  constraint fk_membros_organizacao_usuario
    foreign key (usuario_id) references public.usuarios (id) on delete restrict
);

create index idx_membros_organizacao_usuario on public.membros_organizacao (usuario_id);

create trigger trg_membros_organizacao_atualizado_em
  before update on public.membros_organizacao
  for each row execute function public.definir_atualizado_em();

-- 3) USUARIOS: organizacao ativa + super admin ------------------------------------
-- usuarios.perfil e mantido apenas por compatibilidade com o front e NAO e mais
-- usado para autorizacao. A autorizacao vem de membros_organizacao.
alter table public.usuarios
  add column organizacao_ativa_id uuid,
  add column super_admin boolean not null default false,
  add constraint fk_usuarios_organizacao_ativa
    foreign key (organizacao_ativa_id) references public.organizacoes (id) on delete set null;

-- 4) organizacao_id NAS TABELAS OPERACIONAIS --------------------------------------
alter table public.eventos
  add column organizacao_id uuid not null
  constraint fk_eventos_organizacao references public.organizacoes (id) on delete restrict;
alter table public.lotes
  add column organizacao_id uuid not null
  constraint fk_lotes_organizacao references public.organizacoes (id) on delete restrict;
alter table public.pedidos
  add column organizacao_id uuid not null
  constraint fk_pedidos_organizacao references public.organizacoes (id) on delete restrict;
alter table public.ingressos
  add column organizacao_id uuid not null
  constraint fk_ingressos_organizacao references public.organizacoes (id) on delete restrict;
alter table public.pagamentos
  add column organizacao_id uuid not null
  constraint fk_pagamentos_organizacao references public.organizacoes (id) on delete restrict;
alter table public.entradas
  add column organizacao_id uuid not null
  constraint fk_entradas_organizacao references public.organizacoes (id) on delete restrict;
alter table public.tentativas_entrada
  add column organizacao_id uuid not null
  constraint fk_tentativas_entrada_organizacao references public.organizacoes (id) on delete restrict;
alter table public.cancelamentos_reembolsos
  add column organizacao_id uuid not null
  constraint fk_cancelamentos_reembolsos_organizacao references public.organizacoes (id) on delete restrict;
alter table public.lista_vip
  add column organizacao_id uuid not null
  constraint fk_lista_vip_organizacao references public.organizacoes (id) on delete restrict;
alter table public.entradas_vip
  add column organizacao_id uuid not null
  constraint fk_entradas_vip_organizacao references public.organizacoes (id) on delete restrict;
alter table public.auditoria
  add column organizacao_id uuid
  constraint fk_auditoria_organizacao references public.organizacoes (id) on delete restrict;

create index idx_eventos_organizacao_inicio on public.eventos (organizacao_id, inicio_em desc);
create index idx_lotes_organizacao on public.lotes (organizacao_id);
create index idx_pedidos_organizacao_criado on public.pedidos (organizacao_id, criado_em desc);
create index idx_ingressos_organizacao on public.ingressos (organizacao_id);
create index idx_pagamentos_organizacao on public.pagamentos (organizacao_id);
create index idx_entradas_organizacao on public.entradas (organizacao_id);
create index idx_tentativas_entrada_organizacao on public.tentativas_entrada (organizacao_id);
create index idx_cancelamentos_reembolsos_organizacao on public.cancelamentos_reembolsos (organizacao_id);
create index idx_lista_vip_organizacao on public.lista_vip (organizacao_id);
create index idx_entradas_vip_organizacao on public.entradas_vip (organizacao_id);
create index idx_auditoria_organizacao on public.auditoria (organizacao_id);

-- 5) HELPERS DE IDENTIDADE --------------------------------------------------------

-- Organizacao ativa do usuario autenticado. NULL se: nao autenticado, usuario
-- inativo, sem organizacao ativa, nao e membro ativo dela ou organizacao inativa.
create or replace function private.organizacao_atual_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.organizacao_ativa_id
    from public.usuarios u
    join public.membros_organizacao m
      on m.organizacao_id = u.organizacao_ativa_id
     and m.usuario_id = u.id
     and m.ativo = true
    join public.organizacoes o
      on o.id = u.organizacao_ativa_id
     and o.ativo = true
   where u.id = auth.uid()
     and u.ativo = true;
$$;

-- REDEFINICAO: perfil do usuario NA ORGANIZACAO ATIVA (antes: usuarios.perfil).
-- Mesma assinatura; usuario_e_admin() e usuario_pode_operar_portaria() herdam.
create or replace function private.perfil_usuario_atual()
returns public.perfil_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select m.perfil
    from public.usuarios u
    join public.membros_organizacao m
      on m.usuario_id = u.id
     and m.organizacao_id = u.organizacao_ativa_id
     and m.ativo = true
    join public.organizacoes o
      on o.id = m.organizacao_id
     and o.ativo = true
   where u.id = auth.uid()
     and u.ativo = true;
$$;

-- Super admin da plataforma (suporte / metricas gerais).
create or replace function private.usuario_e_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select u.super_admin
       from public.usuarios u
      where u.id = auth.uid()
        and u.ativo = true),
    false
  );
$$;

-- true se o evento pertence a organizacao ativa do usuario.
create or replace function private.evento_da_organizacao_atual(p_evento_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.eventos e
     where e.id = p_evento_id
       and e.organizacao_id = private.organizacao_atual_id()
  );
$$;

revoke execute on function private.organizacao_atual_id() from public;
revoke execute on function private.usuario_e_super_admin() from public;
revoke execute on function private.evento_da_organizacao_atual(uuid) from public;

-- 6) TRIGGERS DE ORGANIZACAO ------------------------------------------------------

-- eventos: na insercao usa a organizacao ativa se nao informada; imutavel depois.
create or replace function private.definir_organizacao_evento()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.organizacao_id is null then
      new.organizacao_id := private.organizacao_atual_id();
    end if;
    if new.organizacao_id is null then
      raise exception 'Organizacao nao definida para o evento' using errcode = '23502';
    end if;
  elsif new.organizacao_id is distinct from old.organizacao_id then
    raise exception 'Nao e permitido alterar a organizacao do evento' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger trg_eventos_organizacao
  before insert or update of organizacao_id on public.eventos
  for each row execute function private.definir_organizacao_evento();

-- tabelas com evento_id: herda a organizacao do evento e bloqueia divergencia.
create or replace function private.definir_organizacao_por_evento()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_organizacao_id uuid;
begin
  select e.organizacao_id
    into v_organizacao_id
    from public.eventos e
   where e.id = new.evento_id;

  if v_organizacao_id is null then
    raise exception 'Evento inexistente ao definir a organizacao' using errcode = '23503';
  end if;
  if new.organizacao_id is not null and new.organizacao_id <> v_organizacao_id then
    raise exception 'Organizacao divergente da organizacao do evento' using errcode = '23514';
  end if;

  new.organizacao_id := v_organizacao_id;
  return new;
end;
$$;

create trigger trg_lotes_organizacao
  before insert or update of evento_id, organizacao_id on public.lotes
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_pedidos_organizacao
  before insert or update of evento_id, organizacao_id on public.pedidos
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_ingressos_organizacao
  before insert or update of evento_id, organizacao_id on public.ingressos
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_entradas_organizacao
  before insert or update of evento_id, organizacao_id on public.entradas
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_tentativas_entrada_organizacao
  before insert or update of evento_id, organizacao_id on public.tentativas_entrada
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_lista_vip_organizacao
  before insert or update of evento_id, organizacao_id on public.lista_vip
  for each row execute function private.definir_organizacao_por_evento();
create trigger trg_entradas_vip_organizacao
  before insert or update of evento_id, organizacao_id on public.entradas_vip
  for each row execute function private.definir_organizacao_por_evento();

-- tabelas com pedido_id: herda a organizacao do pedido e bloqueia divergencia.
create or replace function private.definir_organizacao_por_pedido()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_organizacao_id uuid;
begin
  select p.organizacao_id
    into v_organizacao_id
    from public.pedidos p
   where p.id = new.pedido_id;

  if v_organizacao_id is null then
    raise exception 'Pedido inexistente ao definir a organizacao' using errcode = '23503';
  end if;
  if new.organizacao_id is not null and new.organizacao_id <> v_organizacao_id then
    raise exception 'Organizacao divergente da organizacao do pedido' using errcode = '23514';
  end if;

  new.organizacao_id := v_organizacao_id;
  return new;
end;
$$;

create trigger trg_pagamentos_organizacao
  before insert or update of pedido_id, organizacao_id on public.pagamentos
  for each row execute function private.definir_organizacao_por_pedido();
create trigger trg_cancelamentos_reembolsos_organizacao
  before insert or update of pedido_id, organizacao_id on public.cancelamentos_reembolsos
  for each row execute function private.definir_organizacao_por_pedido();

-- auditoria: registra a organizacao ativa quando nao informada.
create or replace function private.definir_organizacao_auditoria()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organizacao_id is null then
    new.organizacao_id := private.organizacao_atual_id();
  end if;
  return new;
end;
$$;

create trigger trg_auditoria_organizacao
  before insert on public.auditoria
  for each row execute function private.definir_organizacao_auditoria();

-- membros: primeira associacao vira a organizacao ativa do usuario.
create or replace function private.definir_organizacao_ativa_inicial()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.usuarios u
     set organizacao_ativa_id = new.organizacao_id
   where u.id = new.usuario_id
     and u.organizacao_ativa_id is null;
  return new;
end;
$$;

create trigger trg_membros_organizacao_ativa_inicial
  after insert on public.membros_organizacao
  for each row execute function private.definir_organizacao_ativa_inicial();

revoke execute on function private.definir_organizacao_evento() from public;
revoke execute on function private.definir_organizacao_por_evento() from public;
revoke execute on function private.definir_organizacao_por_pedido() from public;
revoke execute on function private.definir_organizacao_auditoria() from public;
revoke execute on function private.definir_organizacao_ativa_inicial() from public;

-- 7) RLS DAS TABELAS NOVAS (deny-by-default, acesso apenas via RPC) ---------------
alter table public.organizacoes enable row level security;
alter table public.membros_organizacao enable row level security;

revoke all privileges on table public.organizacoes from anon, authenticated;
revoke all privileges on table public.membros_organizacao from anon, authenticated;
