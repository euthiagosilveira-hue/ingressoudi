-- =============================================================================
-- Ingressoudi - Remove tabelas avulsas que nao fazem parte do app
-- (criadas fora das migrations, com permissoes abertas para anon/authenticated).
-- Sem CASCADE: se algo do app depender delas, a migration falha e nada e removido.
-- =============================================================================
drop table if exists public.usuario;
drop table if exists public.fornecedor;
