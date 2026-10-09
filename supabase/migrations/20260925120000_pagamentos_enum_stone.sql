-- =============================================================================
-- GZ1 Ingresso - Pagamentos multi-provedor (1/2): enum
-- Migration: pagamentos_enum_stone
--
-- Adiciona STONE ao enum public.provedor_pagamento, preservando MERCADO_PAGO.
--
-- Isolada em arquivo proprio porque ALTER TYPE ... ADD VALUE nao pode ser
-- utilizado (como valor) na mesma transacao em que e criado. As demais
-- alteracoes (colunas, dados, RPCs) ficam na migration seguinte.
--
-- Idempotente. Sem alteracao de dados. Sem DROP/DELETE/TRUNCATE.
-- =============================================================================

alter type public.provedor_pagamento add value if not exists 'STONE';
