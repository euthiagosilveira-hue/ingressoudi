-- =============================================================================
-- GZ1 Ingresso - Estrutura inicial do banco de dados
-- Migration: estrutura_inicial_gz1_ingresso
--
-- Escopo desta migration:
--   * extensoes
--   * enums
--   * tabelas
--   * primary keys, foreign keys, defaults
--   * constraints simples e condicionais
--   * uniques basicos
--
-- Fora do escopo (etapas futuras):
--   * RLS, policies
--   * RPCs, funcoes transacionais
--   * triggers de negocio, automacoes
--   * views, materialized views, cron/jobs
--   * integracao Mercado Pago, webhooks
--   * seed
--
-- Schema: public
-- Nomenclatura: snake_case, nomes em portugues.
--
-- IMPORTANTE: todas as FKs operacionais usam ON DELETE RESTRICT / NO ACTION.
-- O historico deve ser preservado; operacoes sao de cancelar/encerrar/anular,
-- nunca de exclusao fisica.
-- =============================================================================

-- EXTENSOES -------------------------------------------------------------------
-- gen_random_uuid() e nativo no PostgreSQL 13+ (core). A extensao abaixo e
-- mantida por compatibilidade; "if not exists" a torna idempotente.
create extension if not exists pgcrypto with schema extensions;

-- ENUMS -----------------------------------------------------------------------

create type public.status_evento as enum (
  'AGENDADO',
  'EM_ANDAMENTO',
  'REALIZADO',
  'CANCELADO'
);

create type public.status_vendas as enum (
  'ABERTAS',
  'ENCERRADAS'
);

create type public.status_publicacao as enum (
  'RASCUNHO',
  'PUBLICADO'
);

create type public.tipo_ativacao_lote as enum (
  'MANUAL',
  'ESGOTAMENTO',
  'DATA_HORA'
);

create type public.status_lote as enum (
  'INATIVO',
  'ATIVO',
  'ENCERRADO'
);

create type public.tipo_preco_pedido as enum (
  'LOTE',
  'AVULSO'
);

create type public.status_pedido as enum (
  'RESERVADO',
  'PAGO',
  'EXPIRADO',
  'CANCELADO'
);

create type public.status_ingresso as enum (
  'RESERVADO',
  'VALIDO',
  'UTILIZADO',
  'EXPIRADO',
  'CANCELADO'
);

create type public.provedor_pagamento as enum (
  'MERCADO_PAGO'
);

create type public.status_pagamento as enum (
  'PENDENTE',
  'APROVADO',
  'REJEITADO',
  'CANCELADO',
  'EXPIRADO',
  'REEMBOLSADO'
);

create type public.metodo_validacao as enum (
  'QR_CODE',
  'NOME'
);

create type public.perfil_usuario as enum (
  'ADMINISTRADOR',
  'PORTARIA'
);

create type public.tipo_operacao_financeira as enum (
  'CANCELAMENTO',
  'REEMBOLSO'
);

create type public.status_operacao_financeira as enum (
  'PENDENTE',
  'CONCLUIDO',
  'RECUSADO',
  'FALHOU'
);

create type public.resultado_validacao as enum (
  'LIBERADO',
  'JA_UTILIZADO',
  'INVALIDO',
  'CANCELADO',
  'EVENTO_INCORRETO',
  'NAO_ENCONTRADO'
);

-- USUARIOS --------------------------------------------------------------------
-- Perfil de aplicacao vinculado 1:1 a auth.users.
-- Nao armazenar senha. Nao usar CASCADE.
create table public.usuarios (
  id uuid
    constraint pk_usuarios primary key
    constraint fk_usuarios_auth_users references auth.users (id) on delete restrict,
  nome text not null,
  email text not null
    constraint uq_usuarios_email unique,
  perfil public.perfil_usuario not null,
  ativo boolean not null default true,
  ultimo_acesso_em timestamptz null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- EVENTOS ---------------------------------------------------------------------
create table public.eventos (
  id uuid
    constraint pk_eventos primary key default gen_random_uuid(),
  nome text not null,
  slug text not null
    constraint uq_eventos_slug unique,
  descricao text null,
  imagem_url text null,

  inicio_em timestamptz not null,
  encerrado_em timestamptz null,

  local text not null,
  endereco text not null,

  capacidade_total integer not null,
  estoque_antecipado integer not null,

  status public.status_evento not null default 'AGENDADO',
  vendas_status public.status_vendas not null default 'ENCERRADAS',
  publicacao_status public.status_publicacao not null default 'RASCUNHO',
  publicado_em timestamptz null,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint chk_eventos_capacidade_total check (capacidade_total > 0),
  constraint chk_eventos_estoque_antecipado check (estoque_antecipado >= 0),
  constraint chk_eventos_estoque_antecipado_limite
    check (estoque_antecipado <= capacidade_total),
  constraint chk_eventos_encerrado_em
    check (encerrado_em is null or encerrado_em >= inicio_em)
);

-- LOTES -----------------------------------------------------------------------
create table public.lotes (
  id uuid
    constraint pk_lotes primary key default gen_random_uuid(),
  evento_id uuid not null
    constraint fk_lotes_evento references public.eventos (id) on delete restrict,

  nome text not null,
  ordem integer not null,
  quantidade integer not null,
  preco numeric(10, 2) not null,

  tipo_ativacao public.tipo_ativacao_lote not null,
  ativacao_em timestamptz null,

  ativado_em timestamptz null,
  encerrado_em timestamptz null,

  status public.status_lote not null default 'INATIVO',

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint uq_lotes_evento_ordem unique (evento_id, ordem),
  constraint chk_lotes_ordem check (ordem > 0),
  constraint chk_lotes_quantidade check (quantidade > 0),
  constraint chk_lotes_preco check (preco >= 0),
  -- Se a ativacao for por DATA_HORA, a data/hora de ativacao e obrigatoria.
  constraint chk_lotes_tipo_ativacao
    check (tipo_ativacao <> 'DATA_HORA' or ativacao_em is not null)
);

-- PEDIDOS ---------------------------------------------------------------------
create table public.pedidos (
  id uuid
    constraint pk_pedidos primary key default gen_random_uuid(),
  evento_id uuid not null
    constraint fk_pedidos_evento references public.eventos (id) on delete restrict,
  lote_id uuid null
    constraint fk_pedidos_lote references public.lotes (id) on delete restrict,

  codigo text not null
    constraint uq_pedidos_codigo unique,

  comprador_nome text not null,
  comprador_telefone text not null,
  comprador_email text null,

  quantidade integer not null,

  tipo_preco public.tipo_preco_pedido not null,

  valor_unitario numeric(10, 2) not null,
  valor_total numeric(10, 2) not null,

  motivo_valor_avulso text null,
  autorizado_por_usuario_id uuid null
    constraint fk_pedidos_autorizado_por references public.usuarios (id) on delete restrict,

  status public.status_pedido not null default 'RESERVADO',

  reserva_expira_em timestamptz not null,

  pago_em timestamptz null,
  cancelado_em timestamptz null,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint chk_pedidos_quantidade check (quantidade between 1 and 10),
  constraint chk_pedidos_valor_unitario check (valor_unitario >= 0),
  constraint chk_pedidos_valor_total check (valor_total >= 0),
  -- Regras condicionais por tipo de preco:
  --   LOTE   -> exige lote_id
  --   AVULSO -> nao usa lote, exige motivo e autorizador
  constraint chk_pedidos_tipo_preco check (
    (tipo_preco = 'LOTE' and lote_id is not null)
    or
    (
      tipo_preco = 'AVULSO'
      and lote_id is null
      and motivo_valor_avulso is not null
      and autorizado_por_usuario_id is not null
    )
  )
);

-- INGRESSOS -------------------------------------------------------------------
create table public.ingressos (
  id uuid
    constraint pk_ingressos primary key default gen_random_uuid(),
  pedido_id uuid not null
    constraint fk_ingressos_pedido references public.pedidos (id) on delete restrict,
  evento_id uuid not null
    constraint fk_ingressos_evento references public.eventos (id) on delete restrict,
  lote_id uuid null
    constraint fk_ingressos_lote references public.lotes (id) on delete restrict,

  codigo text not null
    constraint uq_ingressos_codigo unique,
  participante_nome text not null,

  valor_unitario numeric(10, 2) not null,

  qr_token text not null
    constraint uq_ingressos_qr_token unique,

  status public.status_ingresso not null default 'RESERVADO',

  utilizado_em timestamptz null,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint chk_ingressos_valor_unitario check (valor_unitario >= 0)
);

-- PAGAMENTOS ------------------------------------------------------------------
create table public.pagamentos (
  id uuid
    constraint pk_pagamentos primary key default gen_random_uuid(),
  pedido_id uuid not null
    constraint fk_pagamentos_pedido references public.pedidos (id) on delete restrict
    constraint uq_pagamentos_pedido unique,

  provedor public.provedor_pagamento not null default 'MERCADO_PAGO',

  mercado_pago_payment_id text null
    constraint uq_pagamentos_mp_payment_id unique,
  mercado_pago_external_reference text null,

  valor numeric(10, 2) not null,

  status public.status_pagamento not null default 'PENDENTE',

  pix_copia_cola text null,
  pix_qr_code text null,

  expira_em timestamptz null,
  confirmado_em timestamptz null,
  cancelado_em timestamptz null,
  reembolsado_em timestamptz null,

  valor_reembolsado numeric(10, 2) null,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint chk_pagamentos_valor check (valor >= 0),
  constraint chk_pagamentos_valor_reembolsado
    check (valor_reembolsado is null or valor_reembolsado >= 0),
  constraint chk_pagamentos_reembolso_limite
    check (valor_reembolsado is null or valor_reembolsado <= valor)
);

-- ENTRADAS --------------------------------------------------------------------
-- Sem UNIQUE(ingresso_id) e sem indice unico parcial nesta etapa.
create table public.entradas (
  id uuid
    constraint pk_entradas primary key default gen_random_uuid(),
  ingresso_id uuid not null
    constraint fk_entradas_ingresso references public.ingressos (id) on delete restrict,
  evento_id uuid not null
    constraint fk_entradas_evento references public.eventos (id) on delete restrict,
  usuario_id uuid not null
    constraint fk_entradas_usuario references public.usuarios (id) on delete restrict,

  metodo_validacao public.metodo_validacao not null,

  entrada_em timestamptz not null default now(),

  anulada_em timestamptz null,
  anulada_por_usuario_id uuid null
    constraint fk_entradas_anulada_por references public.usuarios (id) on delete restrict,
  motivo_anulacao text null,

  criado_em timestamptz not null default now(),

  -- Se anulada_em preenchido, o autor da anulacao e o motivo sao obrigatorios.
  constraint chk_entradas_anulacao check (
    anulada_em is null
    or (anulada_por_usuario_id is not null and motivo_anulacao is not null)
  )
);

-- CANCELAMENTOS E REEMBOLSOS --------------------------------------------------
create table public.cancelamentos_reembolsos (
  id uuid
    constraint pk_cancelamentos_reembolsos primary key default gen_random_uuid(),
  pedido_id uuid not null
    constraint fk_cancelamentos_reembolsos_pedido
      references public.pedidos (id) on delete restrict,
  pagamento_id uuid null
    constraint fk_cancelamentos_reembolsos_pagamento
      references public.pagamentos (id) on delete restrict,

  tipo public.tipo_operacao_financeira not null,
  status public.status_operacao_financeira not null default 'PENDENTE',

  valor numeric(10, 2) null,
  motivo text not null,
  observacao text null,

  usuario_id uuid not null
    constraint fk_cancelamentos_reembolsos_usuario
      references public.usuarios (id) on delete restrict,

  mercado_pago_refund_id text null,

  solicitado_em timestamptz not null default now(),
  processado_em timestamptz null,

  criado_em timestamptz not null default now(),

  constraint chk_cancelamentos_reembolsos_valor
    check (valor is null or valor >= 0)
);

-- TENTATIVAS DE ENTRADA -------------------------------------------------------
create table public.tentativas_entrada (
  id uuid
    constraint pk_tentativas_entrada primary key default gen_random_uuid(),
  evento_id uuid not null
    constraint fk_tentativas_entrada_evento references public.eventos (id) on delete restrict,
  ingresso_id uuid null
    constraint fk_tentativas_entrada_ingresso references public.ingressos (id) on delete restrict,
  usuario_id uuid not null
    constraint fk_tentativas_entrada_usuario references public.usuarios (id) on delete restrict,

  metodo_validacao public.metodo_validacao not null,
  resultado public.resultado_validacao not null,

  motivo text null,

  criado_em timestamptz not null default now()
);

-- AUDITORIA -------------------------------------------------------------------
-- Sem enum para acao nesta etapa.
create table public.auditoria (
  id uuid
    constraint pk_auditoria primary key default gen_random_uuid(),
  usuario_id uuid null
    constraint fk_auditoria_usuario references public.usuarios (id) on delete restrict,

  acao text not null,
  entidade text not null,
  entidade_id uuid null,

  dados_anteriores jsonb null,
  dados_novos jsonb null,

  observacao text null,

  criado_em timestamptz not null default now()
);
