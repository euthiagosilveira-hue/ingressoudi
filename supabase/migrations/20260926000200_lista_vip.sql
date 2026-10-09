-- =============================================================================
-- GZ1 Ingresso - Lista VIP (schema)
-- Migration: lista_vip
--
-- Lista VIP e uma entidade OPERACIONAL propria, NAO uma venda:
--   * pertence a um evento;
--   * nao possui preco;
--   * nao gera pedido/pagamento/ingresso;
--   * nao entra no financeiro/faturamento;
--   * somente ADMINISTRADOR cadastra/edita/remove;
--   * PORTARIA busca por nome e registra a entrada.
--
-- Tabelas:
--   public.lista_vip      -> nomes convidados (por evento)
--   public.entradas_vip   -> historico de entradas efetivas (1 por convidado)
--
-- Modelagem de status: NAO duplicar estado. O status (AGUARDANDO/ENTROU) e
-- DERIVADO da existencia de entrada ativa em public.entradas_vip. A lista guarda
-- apenas `ativo` para remocao logica (soft-cancel) sem apagar historico.
--
-- Dupla entrada: impedida por indice unico parcial (uma entrada nao anulada por
-- convidado) + lock na linha do convidado na RPC de registro.
--
-- Nao ha FK de lista_vip/entradas_vip para pedidos/pagamentos (separacao total
-- do financeiro). Nenhuma migration aplicada e editada.
-- =============================================================================

-- LISTA VIP -------------------------------------------------------------------
create table public.lista_vip (
  id uuid
    constraint pk_lista_vip primary key default gen_random_uuid(),
  evento_id uuid not null
    constraint fk_lista_vip_evento references public.eventos (id) on delete restrict,

  nome text not null,
  telefone text null,
  observacao text null,

  ativo boolean not null default true,

  criado_por_usuario_id uuid not null
    constraint fk_lista_vip_criado_por references public.usuarios (id) on delete restrict,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint chk_lista_vip_nome check (btrim(nome) <> '')
);

create index idx_lista_vip_evento on public.lista_vip (evento_id);
create index idx_lista_vip_evento_nome on public.lista_vip (evento_id, lower(btrim(nome)));

-- ENTRADAS VIP ----------------------------------------------------------------
create table public.entradas_vip (
  id uuid
    constraint pk_entradas_vip primary key default gen_random_uuid(),
  lista_vip_id uuid not null
    constraint fk_entradas_vip_lista references public.lista_vip (id) on delete restrict,
  evento_id uuid not null
    constraint fk_entradas_vip_evento references public.eventos (id) on delete restrict,
  usuario_id uuid not null
    constraint fk_entradas_vip_usuario references public.usuarios (id) on delete restrict,

  metodo_validacao public.metodo_validacao not null default 'NOME',

  entrada_em timestamptz not null default now(),

  anulada_em timestamptz null,
  anulada_por_usuario_id uuid null
    constraint fk_entradas_vip_anulada_por references public.usuarios (id) on delete restrict,
  motivo_anulacao text null,

  criado_em timestamptz not null default now(),

  constraint chk_entradas_vip_anulacao check (
    anulada_em is null
    or (anulada_por_usuario_id is not null and motivo_anulacao is not null)
  )
);

-- No maximo UMA entrada efetiva (nao anulada) por convidado VIP.
create unique index uq_entradas_vip_ativa
  on public.entradas_vip (lista_vip_id)
  where anulada_em is null;

create index idx_entradas_vip_evento on public.entradas_vip (evento_id);

-- CONSISTENCIA ----------------------------------------------------------------
-- evento da entrada VIP deve ser o evento da lista VIP.
create or replace function public.validar_entrada_vip()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_evento_id uuid;
begin
  select lv.evento_id
    into v_evento_id
    from public.lista_vip lv
   where lv.id = new.lista_vip_id;

  if not found then
    raise exception
      'Entrada VIP % : lista % nao encontrada',
      new.id, new.lista_vip_id
      using errcode = '23503';
  end if;

  if new.evento_id <> v_evento_id then
    raise exception
      'Entrada VIP % : evento % difere do evento % da lista VIP %',
      new.id, new.evento_id, v_evento_id, new.lista_vip_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger trg_validar_entrada_vip
  before insert or update on public.entradas_vip
  for each row execute function public.validar_entrada_vip();

-- RLS / ACESSO DIRETO ---------------------------------------------------------
-- DENY BY DEFAULT: nenhum acesso direto as tabelas; tudo via RPC SECURITY DEFINER.
alter table public.lista_vip enable row level security;
alter table public.entradas_vip enable row level security;

revoke all privileges on table public.lista_vip from public, anon, authenticated;
revoke all privileges on table public.entradas_vip from public, anon, authenticated;

comment on table public.lista_vip is
  'Lista VIP do evento (convidados sem preco/pedido/pagamento). Status derivado de entradas_vip.';
comment on table public.entradas_vip is
  'Historico de entradas efetivas de convidados VIP. Uma entrada ativa por convidado.';
