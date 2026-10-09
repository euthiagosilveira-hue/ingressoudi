-- =============================================================================
-- GZ1 Ingresso - Fechar ACL de portaria/admin (corretiva)
-- Migration: fechar_acl_portaria_admin
--
-- Contexto: as novas wrappers public de portaria/admin criadas em
-- ponte_rpc_operacional herdaram, pelas *default privileges* do schema public,
-- EXECUTE para anon/authenticated/service_role. O "REVOKE ... FROM PUBLIC" nao
-- remove o grant explicito para anon. Esta migration remove EXECUTE de anon
-- (e de PUBLIC, defensivamente) nessas wrappers, mantendo authenticated e
-- service_role.
--
-- Nao altera logica. Nao ativa RLS. Nao mexe em tabelas/sequence/frontend.
-- =============================================================================

revoke execute on function public.registrar_entrada_qr(uuid, text) from public, anon;
revoke execute on function public.registrar_entrada_nome(uuid, uuid) from public, anon;
revoke execute on function public.buscar_ingressos_por_nome(uuid, text) from public, anon;
revoke execute on function public.ativar_lote_manual(uuid) from public, anon;
revoke execute on function public.encerrar_evento(uuid) from public, anon;
revoke execute on function public.anular_entrada(uuid, text) from public, anon;

grant execute on function public.registrar_entrada_qr(uuid, text) to authenticated, service_role;
grant execute on function public.registrar_entrada_nome(uuid, uuid) to authenticated, service_role;
grant execute on function public.buscar_ingressos_por_nome(uuid, text) to authenticated, service_role;
grant execute on function public.ativar_lote_manual(uuid) to authenticated, service_role;
grant execute on function public.encerrar_evento(uuid) to authenticated, service_role;
grant execute on function public.anular_entrada(uuid, text) to authenticated, service_role;
