-- =============================================================================
-- GZ1 Ingresso - Venda manual: telefone do comprador passa a ser opcional
-- Migration: venda_manual_telefone_opcional
--
-- public.pedidos.comprador_telefone deixa de ser NOT NULL para permitir venda
-- manual administrativa sem telefone.
--
-- IMPORTANTE - impacto no checkout publico:
--   * O fluxo publico NAO muda. private.criar_reserva continua validando
--     telefone obrigatorio (raise 'comprador_telefone obrigatorio') e a UI de
--     checkout publico continua exigindo telefone valido.
--   * public.recuperacao_ingressos ja trata telefone nulo via coalesce.
--   * A listagem/detalhe admin ja lidam com telefone nulo (formatarTelefone).
--
-- Nenhuma migration aplicada e editada. Sem DROP/DELETE/TRUNCATE.
-- =============================================================================

alter table public.pedidos alter column comprador_telefone drop not null;

comment on column public.pedidos.comprador_telefone is
  'Telefone do comprador. Obrigatorio no checkout publico (validado na RPC criar_reserva). Opcional em venda manual administrativa.';
