-- =============================================================================
-- GZ1 Ingresso - Eventos operacionais da portaria
-- Migration: eventos_portaria
--
-- Objetivo: listar eventos relevantes para a portaria (AGENDADO/EM_ANDAMENTO)
-- para a selecao real no scanner, SEM abrir SELECT direto em public.eventos.
--
-- Escopo:
--   * private.listar_eventos_portaria()  (SECURITY DEFINER; exige perfil)
--   * public.listar_eventos_portaria()   (SECURITY INVOKER)
--   * ACL: apenas authenticated/service_role
--
-- Nao altera tabelas/RLS. Nao afrouxa ACL existente. Retorna apenas campos de
-- operacao (sem dados financeiros).
-- Padrao: public SECURITY INVOKER -> private SECURITY DEFINER, search_path=''.
-- =============================================================================

create or replace function private.listar_eventos_portaria()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_itens jsonb;
begin
  if not private.usuario_pode_operar_portaria() then
    raise exception 'Permissao negada para operar portaria' using errcode = '42501';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'evento_id', e.id,
               'nome', e.nome,
               'inicio_em', e.inicio_em,
               'local', e.local,
               'status', e.status
             ) order by e.inicio_em
           ),
           '[]'::jsonb
         )
    into v_itens
    from public.eventos e
   where e.status in ('AGENDADO', 'EM_ANDAMENTO');

  return v_itens;
end;
$$;

create or replace function public.listar_eventos_portaria()
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.listar_eventos_portaria();
$$;

grant usage on schema private to authenticated, service_role;

revoke all on function private.listar_eventos_portaria() from public;
grant execute on function private.listar_eventos_portaria() to authenticated, service_role;

revoke execute on function public.listar_eventos_portaria()
  from public, anon, authenticated, service_role;
grant execute on function public.listar_eventos_portaria() to authenticated, service_role;

comment on function public.listar_eventos_portaria() is
  'Lista eventos operacionais (AGENDADO/EM_ANDAMENTO) para a portaria. '
  'Exige usuario autenticado com perfil ADMINISTRADOR ou PORTARIA.';
