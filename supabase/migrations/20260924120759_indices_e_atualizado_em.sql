-- =============================================================================
-- GZ1 Ingresso - Indices e atualizado_em
-- Migration: indices_e_atualizado_em
--
-- Escopo desta migration:
--   * funcao generica public.definir_atualizado_em()
--   * 6 triggers BEFORE UPDATE para atualizado_em
--   * indices unicos parciais:
--       - um unico lote ATIVO por evento
--       - uma unica entrada nao anulada por ingresso
--   * indices de consulta/performance
--
-- Fora do escopo (etapas futuras):
--   * RLS, policies, RPCs, views, cron/jobs
--   * regras de negocio (soma de lotes, expiracao, transicoes automaticas)
--   * Mercado Pago, webhooks, seed
--
-- Nao ha DROP, DELETE ou ALTER destrutivo.
-- =============================================================================

-- FUNCAO atualizado_em --------------------------------------------------------
-- Uso exclusivo das tabelas que possuem a coluna atualizado_em.
create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

-- TRIGGERS atualizado_em ------------------------------------------------------
create trigger trg_usuarios_atualizado_em
  before update on public.usuarios
  for each row execute function public.definir_atualizado_em();

create trigger trg_eventos_atualizado_em
  before update on public.eventos
  for each row execute function public.definir_atualizado_em();

create trigger trg_lotes_atualizado_em
  before update on public.lotes
  for each row execute function public.definir_atualizado_em();

create trigger trg_pedidos_atualizado_em
  before update on public.pedidos
  for each row execute function public.definir_atualizado_em();

create trigger trg_ingressos_atualizado_em
  before update on public.ingressos
  for each row execute function public.definir_atualizado_em();

create trigger trg_pagamentos_atualizado_em
  before update on public.pagamentos
  for each row execute function public.definir_atualizado_em();

-- INDICES UNICOS PARCIAIS -----------------------------------------------------
-- Impede dois lotes ATIVOS simultaneos no mesmo evento.
create unique index uq_lotes_evento_ativo
  on public.lotes (evento_id)
  where status = 'ATIVO';

-- Permite historico de entradas anuladas, mas so uma entrada nao anulada.
create unique index uq_entradas_ingresso_ativa
  on public.entradas (ingresso_id)
  where anulada_em is null;

-- INDICES: EVENTOS ------------------------------------------------------------
create index idx_eventos_status on public.eventos (status);
create index idx_eventos_vendas_status on public.eventos (vendas_status);
create index idx_eventos_publicacao_status on public.eventos (publicacao_status);
create index idx_eventos_inicio_em on public.eventos (inicio_em);

-- INDICES: LOTES --------------------------------------------------------------
-- idx_lotes_evento omitido: uq_lotes_evento_ordem (evento_id, ordem) ja cobre
-- consultas por evento_id (coluna prefixo).
create index idx_lotes_evento_status on public.lotes (evento_id, status);
create index idx_lotes_ativacao_em on public.lotes (ativacao_em);

-- INDICES: PEDIDOS ------------------------------------------------------------
-- idx_pedidos_evento omitido: idx_pedidos_evento_status (evento_id, status)
-- ja cobre consultas por evento_id.
create index idx_pedidos_status on public.pedidos (status);
create index idx_pedidos_evento_status on public.pedidos (evento_id, status);
create index idx_pedidos_reserva_expira_em on public.pedidos (reserva_expira_em);
create index idx_pedidos_criado_em on public.pedidos (criado_em);

-- INDICES: INGRESSOS ----------------------------------------------------------
-- idx_ingressos_evento omitido: idx_ingressos_evento_status (evento_id, status)
-- ja cobre consultas por evento_id.
create index idx_ingressos_pedido on public.ingressos (pedido_id);
create index idx_ingressos_lote on public.ingressos (lote_id);
create index idx_ingressos_status on public.ingressos (status);
create index idx_ingressos_evento_status on public.ingressos (evento_id, status);
-- Busca por nome na portaria (B-tree simples; sem extensao de busca textual).
create index idx_ingressos_participante_nome on public.ingressos (participante_nome);

-- INDICES: PAGAMENTOS ---------------------------------------------------------
-- pedido_id e mercado_pago_payment_id omitidos: ja possuem UNIQUE.
create index idx_pagamentos_status on public.pagamentos (status);
create index idx_pagamentos_criado_em on public.pagamentos (criado_em);
create index idx_pagamentos_mp_external_reference
  on public.pagamentos (mercado_pago_external_reference);

-- INDICES: ENTRADAS -----------------------------------------------------------
-- idx_entradas_evento omitido: idx_entradas_evento_entrada_em
-- (evento_id, entrada_em) ja cobre consultas por evento_id.
create index idx_entradas_usuario on public.entradas (usuario_id);
create index idx_entradas_entrada_em on public.entradas (entrada_em);
create index idx_entradas_evento_entrada_em on public.entradas (evento_id, entrada_em);

-- INDICES: TENTATIVAS DE ENTRADA ----------------------------------------------
-- idx_tentativas_entrada_evento omitido: idx_tentativas_entrada_evento_criado_em
-- (evento_id, criado_em) ja cobre consultas por evento_id.
create index idx_tentativas_entrada_ingresso on public.tentativas_entrada (ingresso_id);
create index idx_tentativas_entrada_usuario on public.tentativas_entrada (usuario_id);
create index idx_tentativas_entrada_resultado on public.tentativas_entrada (resultado);
create index idx_tentativas_entrada_criado_em on public.tentativas_entrada (criado_em);
create index idx_tentativas_entrada_evento_criado_em
  on public.tentativas_entrada (evento_id, criado_em);

-- INDICES: CANCELAMENTOS E REEMBOLSOS -----------------------------------------
create index idx_cancelamentos_reembolsos_pedido
  on public.cancelamentos_reembolsos (pedido_id);
create index idx_cancelamentos_reembolsos_pagamento
  on public.cancelamentos_reembolsos (pagamento_id);
create index idx_cancelamentos_reembolsos_usuario
  on public.cancelamentos_reembolsos (usuario_id);
create index idx_cancelamentos_reembolsos_status
  on public.cancelamentos_reembolsos (status);
create index idx_cancelamentos_reembolsos_criado_em
  on public.cancelamentos_reembolsos (criado_em);

-- INDICES: AUDITORIA ----------------------------------------------------------
create index idx_auditoria_usuario on public.auditoria (usuario_id);
create index idx_auditoria_entidade on public.auditoria (entidade, entidade_id);
create index idx_auditoria_criado_em on public.auditoria (criado_em);
create index idx_auditoria_acao on public.auditoria (acao);
