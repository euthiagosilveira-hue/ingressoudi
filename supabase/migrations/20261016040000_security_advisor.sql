-- =============================================================================
-- Ingressoudi - Seguranca (Security Advisor do Supabase)
--  1) 11 RPCs antigas eram SECURITY DEFINER direto no schema public (exposto).
--     Passam para o padrao do projeto: implementacao em private (definer, com as
--     mesmas checagens) + wrapper em public SECURITY INVOKER. Assinaturas,
--     defaults e retorno identicos: o front nao muda.
--  2) definir_atualizado_em com search_path fixo.
--  3) usuarios: sem leitura direta (o app le o perfil pela RPC obter_sessao_operador;
--     o servidor usa service_role). Some do schema GraphQL.
--  4) Bucket eventos-capas: arquivos continuam publicos pela URL, mas a listagem
--     do bucket fica restrita ao administrador, na pasta da propria casa.
-- =============================================================================

-- 1) SECURITY DEFINER fora do schema public ------------------------------------
alter function public.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean) set schema private;
create or replace function public.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean)
returns jsonb language sql volatile security invoker set search_path = ''
as $w$ select private.atualizar_usuario_admin(p_usuario_id, p_nome, p_perfil, p_ativo); $w$;
revoke all on function private.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean) from public, anon;
revoke all on function public.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean) from public, anon;
grant execute on function private.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean) to authenticated, service_role;
grant execute on function public.atualizar_usuario_admin(p_usuario_id uuid, p_nome text, p_perfil perfil_usuario, p_ativo boolean) to authenticated, service_role;

alter function public.criar_evento_admin(p_nome text, p_slug text, p_descricao text, p_imagem_url text, p_inicio_em timestamp with time zone, p_local text, p_endereco text, p_capacidade_total integer, p_estoque_antecipado integer, p_publicacao_status status_publicacao, p_vendas_status status_vendas) set schema private;
create or replace function public.criar_evento_admin(p_nome text, p_slug text, p_descricao text DEFAULT NULL::text, p_imagem_url text DEFAULT NULL::text, p_inicio_em timestamp with time zone DEFAULT NULL::timestamp with time zone, p_local text DEFAULT NULL::text, p_endereco text DEFAULT NULL::text, p_capacidade_total integer DEFAULT NULL::integer, p_estoque_antecipado integer DEFAULT NULL::integer, p_publicacao_status status_publicacao DEFAULT 'RASCUNHO'::status_publicacao, p_vendas_status status_vendas DEFAULT 'ENCERRADAS'::status_vendas)
returns jsonb language sql volatile security invoker set search_path = ''
as $w$ select private.criar_evento_admin(p_nome, p_slug, p_descricao, p_imagem_url, p_inicio_em, p_local, p_endereco, p_capacidade_total, p_estoque_antecipado, p_publicacao_status, p_vendas_status); $w$;
revoke all on function private.criar_evento_admin(p_nome text, p_slug text, p_descricao text, p_imagem_url text, p_inicio_em timestamp with time zone, p_local text, p_endereco text, p_capacidade_total integer, p_estoque_antecipado integer, p_publicacao_status status_publicacao, p_vendas_status status_vendas) from public, anon;
revoke all on function public.criar_evento_admin(p_nome text, p_slug text, p_descricao text, p_imagem_url text, p_inicio_em timestamp with time zone, p_local text, p_endereco text, p_capacidade_total integer, p_estoque_antecipado integer, p_publicacao_status status_publicacao, p_vendas_status status_vendas) from public, anon;
grant execute on function private.criar_evento_admin(p_nome text, p_slug text, p_descricao text, p_imagem_url text, p_inicio_em timestamp with time zone, p_local text, p_endereco text, p_capacidade_total integer, p_estoque_antecipado integer, p_publicacao_status status_publicacao, p_vendas_status status_vendas) to authenticated, service_role;
grant execute on function public.criar_evento_admin(p_nome text, p_slug text, p_descricao text, p_imagem_url text, p_inicio_em timestamp with time zone, p_local text, p_endereco text, p_capacidade_total integer, p_estoque_antecipado integer, p_publicacao_status status_publicacao, p_vendas_status status_vendas) to authenticated, service_role;

alter function public.listar_entradas_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_metodo metodo_validacao, p_situacao text) set schema private;
create or replace function public.listar_entradas_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_metodo metodo_validacao DEFAULT NULL::metodo_validacao, p_situacao text DEFAULT NULL::text)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.listar_entradas_admin(p_evento_id, p_busca, p_de, p_ate, p_metodo, p_situacao); $w$;
revoke all on function private.listar_entradas_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_metodo metodo_validacao, p_situacao text) from public, anon;
revoke all on function public.listar_entradas_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_metodo metodo_validacao, p_situacao text) from public, anon;
grant execute on function private.listar_entradas_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_metodo metodo_validacao, p_situacao text) to authenticated, service_role;
grant execute on function public.listar_entradas_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_metodo metodo_validacao, p_situacao text) to authenticated, service_role;

alter function public.listar_ingressos_admin(p_evento_id uuid, p_pedido_id uuid, p_busca text, p_status status_ingresso) set schema private;
create or replace function public.listar_ingressos_admin(p_evento_id uuid DEFAULT NULL::uuid, p_pedido_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_status status_ingresso DEFAULT NULL::status_ingresso)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.listar_ingressos_admin(p_evento_id, p_pedido_id, p_busca, p_status); $w$;
revoke all on function private.listar_ingressos_admin(p_evento_id uuid, p_pedido_id uuid, p_busca text, p_status status_ingresso) from public, anon;
revoke all on function public.listar_ingressos_admin(p_evento_id uuid, p_pedido_id uuid, p_busca text, p_status status_ingresso) from public, anon;
grant execute on function private.listar_ingressos_admin(p_evento_id uuid, p_pedido_id uuid, p_busca text, p_status status_ingresso) to authenticated, service_role;
grant execute on function public.listar_ingressos_admin(p_evento_id uuid, p_pedido_id uuid, p_busca text, p_status status_ingresso) to authenticated, service_role;

alter function public.listar_pedidos_admin(p_evento_id uuid, p_busca text, p_status status_pedido, p_pagamento_status status_pagamento, p_tipo_preco tipo_preco_pedido, p_de timestamp with time zone, p_ate timestamp with time zone) set schema private;
create or replace function public.listar_pedidos_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_status status_pedido DEFAULT NULL::status_pedido, p_pagamento_status status_pagamento DEFAULT NULL::status_pagamento, p_tipo_preco tipo_preco_pedido DEFAULT NULL::tipo_preco_pedido, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.listar_pedidos_admin(p_evento_id, p_busca, p_status, p_pagamento_status, p_tipo_preco, p_de, p_ate); $w$;
revoke all on function private.listar_pedidos_admin(p_evento_id uuid, p_busca text, p_status status_pedido, p_pagamento_status status_pagamento, p_tipo_preco tipo_preco_pedido, p_de timestamp with time zone, p_ate timestamp with time zone) from public, anon;
revoke all on function public.listar_pedidos_admin(p_evento_id uuid, p_busca text, p_status status_pedido, p_pagamento_status status_pagamento, p_tipo_preco tipo_preco_pedido, p_de timestamp with time zone, p_ate timestamp with time zone) from public, anon;
grant execute on function private.listar_pedidos_admin(p_evento_id uuid, p_busca text, p_status status_pedido, p_pagamento_status status_pagamento, p_tipo_preco tipo_preco_pedido, p_de timestamp with time zone, p_ate timestamp with time zone) to authenticated, service_role;
grant execute on function public.listar_pedidos_admin(p_evento_id uuid, p_busca text, p_status status_pedido, p_pagamento_status status_pagamento, p_tipo_preco tipo_preco_pedido, p_de timestamp with time zone, p_ate timestamp with time zone) to authenticated, service_role;

alter function public.listar_usuarios_admin(p_busca text) set schema private;
create or replace function public.listar_usuarios_admin(p_busca text DEFAULT NULL::text)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.listar_usuarios_admin(p_busca); $w$;
revoke all on function private.listar_usuarios_admin(p_busca text) from public, anon;
revoke all on function public.listar_usuarios_admin(p_busca text) from public, anon;
grant execute on function private.listar_usuarios_admin(p_busca text) to authenticated, service_role;
grant execute on function public.listar_usuarios_admin(p_busca text) to authenticated, service_role;

alter function public.obter_contadores_admin() set schema private;
create or replace function public.obter_contadores_admin()
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.obter_contadores_admin(); $w$;
revoke all on function private.obter_contadores_admin() from public, anon;
revoke all on function public.obter_contadores_admin() from public, anon;
grant execute on function private.obter_contadores_admin() to authenticated, service_role;
grant execute on function public.obter_contadores_admin() to authenticated, service_role;

alter function public.obter_dashboard_admin() set schema private;
create or replace function public.obter_dashboard_admin()
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.obter_dashboard_admin(); $w$;
revoke all on function private.obter_dashboard_admin() from public, anon;
revoke all on function public.obter_dashboard_admin() from public, anon;
grant execute on function private.obter_dashboard_admin() to authenticated, service_role;
grant execute on function public.obter_dashboard_admin() to authenticated, service_role;

alter function public.obter_financeiro_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_status_pagamento status_pagamento, p_provedor provedor_pagamento) set schema private;
create or replace function public.obter_financeiro_admin(p_evento_id uuid DEFAULT NULL::uuid, p_busca text DEFAULT NULL::text, p_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ate timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status_pagamento status_pagamento DEFAULT NULL::status_pagamento, p_provedor provedor_pagamento DEFAULT NULL::provedor_pagamento)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.obter_financeiro_admin(p_evento_id, p_busca, p_de, p_ate, p_status_pagamento, p_provedor); $w$;
revoke all on function private.obter_financeiro_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_status_pagamento status_pagamento, p_provedor provedor_pagamento) from public, anon;
revoke all on function public.obter_financeiro_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_status_pagamento status_pagamento, p_provedor provedor_pagamento) from public, anon;
grant execute on function private.obter_financeiro_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_status_pagamento status_pagamento, p_provedor provedor_pagamento) to authenticated, service_role;
grant execute on function public.obter_financeiro_admin(p_evento_id uuid, p_busca text, p_de timestamp with time zone, p_ate timestamp with time zone, p_status_pagamento status_pagamento, p_provedor provedor_pagamento) to authenticated, service_role;

alter function public.obter_ingresso_admin(p_ingresso_id uuid) set schema private;
create or replace function public.obter_ingresso_admin(p_ingresso_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.obter_ingresso_admin(p_ingresso_id); $w$;
revoke all on function private.obter_ingresso_admin(p_ingresso_id uuid) from public, anon;
revoke all on function public.obter_ingresso_admin(p_ingresso_id uuid) from public, anon;
grant execute on function private.obter_ingresso_admin(p_ingresso_id uuid) to authenticated, service_role;
grant execute on function public.obter_ingresso_admin(p_ingresso_id uuid) to authenticated, service_role;

alter function public.obter_pedido_admin(p_pedido_id uuid) set schema private;
create or replace function public.obter_pedido_admin(p_pedido_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $w$ select private.obter_pedido_admin(p_pedido_id); $w$;
revoke all on function private.obter_pedido_admin(p_pedido_id uuid) from public, anon;
revoke all on function public.obter_pedido_admin(p_pedido_id uuid) from public, anon;
grant execute on function private.obter_pedido_admin(p_pedido_id uuid) to authenticated, service_role;
grant execute on function public.obter_pedido_admin(p_pedido_id uuid) to authenticated, service_role;


-- 2) search_path fixo ---------------------------------------------------------
alter function public.definir_atualizado_em() set search_path = '';

-- 3) usuarios sem leitura direta ----------------------------------------------
drop policy if exists usuarios_select_proprio on public.usuarios;
revoke all privileges on table public.usuarios from anon, authenticated;

-- 4) storage: sem listagem publica do bucket de capas ---------------------------
drop policy if exists eventos_capas_leitura_publica on storage.objects;
create policy eventos_capas_select_admin
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'eventos-capas'
    and private.usuario_e_admin()
    and (storage.foldername(name))[1] = (private.organizacao_atual_id())::text
  );
