-- =============================================================================
-- Ingressoudi - Perfil "Socio do Evento" (parte 1 de 2)
--
-- Novo valor do enum public.perfil_usuario: SOCIO.
-- Fica sozinho neste arquivo porque o Postgres so deixa USAR um valor novo de
-- enum depois que o ALTER TYPE foi confirmado (commit). A parte 2
-- (20261109030000_socio_evento_vendas.sql) cria a tabela e as RPCs.
--
-- O SOCIO nao passa em nenhuma regra existente: usuario_e_admin() exige
-- ADMINISTRADOR e usuario_pode_operar_portaria() exige ADMINISTRADOR/PORTARIA.
-- =============================================================================

alter type public.perfil_usuario add value if not exists 'SOCIO';
